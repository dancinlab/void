import Cocoa
import VoidKit

/// P7 Phase B2 follow-up: synchronous "live surface UUID set" anchor.
///
/// Background: NSWindowRestoration writes the SplitTree (and its surface UUIDs)
/// to disk asynchronously, on AppKit's schedule. The persist ring at
/// `~/.void/sessions/by-uuid/<uuid>.ring` is mmap'd and updated synchronously
/// per byte. The result is a flush-rate mismatch: if the app dies after a new
/// surface has been writing to its ring but before AppKit has flushed the
/// updated SplitTree, the UUID is missing from the restored topology and the
/// ring becomes a silent orphan — content on disk, but nothing to mount it on.
///
/// This manifest closes that gap by writing the current live UUID set
/// synchronously on every surface-tree change. On the next launch we read this
/// "previous session" snapshot before NSWindowRestoration runs, then triage:
///   prev ∩ restored = recovered cleanly
///   prev - restored = AppKit flush lag loss (ring exists, topology gone)
///   disk - prev     = orphans from sessions older than the last one
///
/// Initial cut is observation only (logging). Auto-GC and user-visible recovery
/// affordances come in follow-ups.
enum SessionManifest {
    static let logger = AppDelegate.logger

    struct Snapshot: Codable {
        let version: Int
        let epochNs: UInt64
        let surfaces: [String]
    }

    /// The previous-session snapshot, captured once at app launch before
    /// AppKit restoration runs. Read by triage(); nil if no manifest existed.
    private(set) static var previousSession: Snapshot?

    /// Path to the manifest file. Lives alongside the ring directory so a
    /// `rm -rf ~/.void/sessions` resets both halves of the recovery state.
    private static var manifestURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".void", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("last.json", isDirectory: false)
    }

    private static var ringDirectoryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".void", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("by-uuid", isDirectory: true)
    }

    /// Snapshot the on-disk manifest into `previousSession`. Call once during
    /// `applicationWillFinishLaunching`, BEFORE NSWindowRestoration runs so
    /// later refreshes don't overwrite the prior-session state we need for
    /// triage. Idempotent — re-calls are no-ops if already captured.
    static func captureFromDisk() {
        guard previousSession == nil else { return }
        previousSession = readFromDisk()
        if let s = previousSession {
            logger.info("session-manifest: captured prior session with \(s.surfaces.count) surface(s)")
        } else {
            logger.info("session-manifest: no prior session on disk")
        }
    }

    /// Enqueue a manifest refresh on the next main-runloop tick. Deferred so
    /// callers from `BaseTerminalController.init` see the controller after it
    /// has been attached to NSApp.windows (during init, super.init(window:nil)
    /// is called and the controller isn't enumerable yet). Coalesces rapid-
    /// fire tree changes — the last write within a tick wins.
    static func refreshFromCurrentControllers() {
        if refreshScheduled { return }
        refreshScheduled = true
        DispatchQueue.main.async {
            refreshScheduled = false
            let uuids = NSApp.windows.flatMap { window -> [String] in
                guard let controller = window.windowController as? BaseTerminalController else {
                    return []
                }
                return controller.surfaceTree.map { $0.id.uuidString }
            }
            write(uuids: uuids)
        }
    }

    private static var refreshScheduled = false

    /// Result of the launch-time triage. All three sets are disjoint.
    struct Triage {
        /// Found in prior manifest AND back in the restored topology — happy path.
        let recovered: Set<String>
        /// In prior manifest but NOT restored. Their ring files exist on disk
        /// but no SurfaceView claimed them — silent loss without intervention.
        let topologyLost: Set<String>
        /// On disk but never in the prior manifest. Orphans from sessions older
        /// than the last one; safe to GC (NOT done automatically in this cut).
        let staleOrphans: Set<String>
    }

    /// Compute the triage given the currently-live restored UUIDs. Pass a
    /// snapshot of UUIDs from `NSApp.windows` after restoration has settled.
    static func triage(restoredUUIDs: Set<String>) -> Triage {
        let prev = Set(previousSession?.surfaces ?? [])
        let disk = readRingUUIDsFromDisk()

        let recovered = prev.intersection(restoredUUIDs)
        let topologyLost = prev.subtracting(restoredUUIDs).intersection(disk)
        let staleOrphans = disk.subtracting(prev)

        return Triage(
            recovered: recovered,
            topologyLost: topologyLost,
            staleOrphans: staleOrphans
        )
    }

    // MARK: - I/O

    private static func write(uuids: [String]) {
        let snapshot = Snapshot(
            version: 1,
            epochNs: UInt64(Date().timeIntervalSince1970 * 1_000_000_000),
            surfaces: uuids
        )

        let url = manifestURL
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        } catch {
            logger.warning("session-manifest: mkdir \(dir.path) err=\(error)")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            logger.warning("session-manifest: encode err=\(error)")
            return
        }

        let tmp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: [.atomic])
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            logger.warning("session-manifest: write \(url.path) err=\(error)")
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private static func readFromDisk() -> Snapshot? {
        let url = manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            logger.warning("session-manifest: read \(url.path) err=\(error)")
            return nil
        }
    }

    private static func readRingUUIDsFromDisk() -> Set<String> {
        let dir = ringDirectoryURL
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            logger.warning("session-manifest: list \(dir.path) err=\(error)")
            return []
        }

        var uuids: Set<String> = []
        for url in contents {
            let name = url.lastPathComponent
            guard name.hasSuffix(".ring") else { continue }
            let stem = String(name.dropLast(".ring".count))
            // Validate it's actually a UUID-shaped string. Anything else is
            // foreign and shouldn't be GC'd as an "orphan".
            guard UUID(uuidString: stem) != nil else { continue }
            uuids.insert(stem)
        }
        return uuids
    }
}
