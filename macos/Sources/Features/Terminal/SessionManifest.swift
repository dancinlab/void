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
            let current = Set(uuids)

            // Reclaim rings for surfaces that left EVERY window this session —
            // i.e. real user-initiated closes (Cmd-W, close tab/window). They
            // were live a moment ago and are now gone from all windows, so their
            // 4MB ring is dead weight that would otherwise sit on disk until the
            // conservative launch-time auto-GC eventually reaps it.
            //
            // Safety:
            //   - `liveLastSet` starts empty, so prior-session rings that were
            //     never live this session (incl. topologyLost) are NEVER deleted
            //     here — they remain for the recovery alert / GC.
            //   - Guarded by `isTerminating`: a graceful quit/restart keeps every
            //     live ring on disk for cold-restore.
            //   - A surface migrating between windows stays in `current` (we scan
            //     all windows), so migration is not mistaken for a close.
            let closed = ringsToReclaim(
                previousLive: liveLastSet,
                currentLive: current,
                isTerminating: isTerminating)
            if !closed.isEmpty { deleteRings(closed) }
            liveLastSet = current

            write(uuids: uuids)
        }
    }

    private static var refreshScheduled = false

    /// Live UUID set as of the previous refresh. Diffed against the next refresh
    /// to detect surfaces closed during a running session. Empty until the first
    /// refresh so launch/restore never triggers a delete.
    private static var liveLastSet: Set<String> = []

    /// True once the app has begun terminating. While set, surface teardown does
    /// NOT reclaim rings — a graceful quit/restart preserves them for cold-restore.
    static var isTerminating = false

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

    // MARK: - Auto-GC of stale orphan rings

    /// On-disk counter mapping `uuid → consecutive_orphan_launches`. Lives at
    /// `~/.void/sessions/gc-counter.json` so a `rm -rf ~/.void/sessions`
    /// resets both rings AND counter state in one shot.
    private static var gcCounterURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".void", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("gc-counter.json", isDirectory: false)
    }

    /// Sanity cap — never delete more than this many rings in a single launch
    /// even if the counter says we should. Protects against a corrupt-but-
    /// parseable counter file from wiping the whole `by-uuid/` tree.
    private static let gcMaxDeletionsPerLaunch = 50

    /// Conservative auto-GC of `staleOrphans`. NEVER touches `topologyLost`.
    /// Counter math: increment for every UUID in `triage.staleOrphans`, reset
    /// (drop) entries for UUIDs not currently orphan, and prune entries for
    /// UUIDs no longer on disk. When `count >= threshold` the ring file is
    /// deleted and the counter entry removed.
    ///
    /// `threshold == 0` is a no-op (opt-out). If the counter file is corrupt
    /// it is deleted and ALL counters reset — better to leak disk for one
    /// launch than to wrongly delete a user's session content.
    static func runAutoGC(triage: Triage, threshold: Int) {
        guard threshold > 0 else { return }

        let orphans = triage.staleOrphans
        let onDisk = readRingUUIDsFromDisk()

        // Load (or reset on corruption) the counter map.
        var counters = readGCCounters()

        // Drop entries for UUIDs no longer on disk (someone or something else
        // removed them already — manual rm, replay tool, prior GC pass).
        counters = counters.filter { onDisk.contains($0.key) }

        // Reset (drop) entries for UUIDs that are no longer orphans this
        // launch — they got referenced by a manifest, so the streak is broken.
        // Then increment for current orphans. Order matters: filter first so
        // a UUID that re-orphans cleanly starts back at 1.
        counters = counters.filter { orphans.contains($0.key) }
        for uuid in orphans {
            counters[uuid, default: 0] += 1
        }

        // Collect deletion candidates, capped for safety.
        var toDelete: [String] = []
        for (uuid, n) in counters where n >= threshold {
            toDelete.append(uuid)
        }
        toDelete.sort()  // deterministic logging order

        var capped = false
        if toDelete.count > Self.gcMaxDeletionsPerLaunch {
            capped = true
            toDelete = Array(toDelete.prefix(Self.gcMaxDeletionsPerLaunch))
        }

        // Execute deletions. Drop counter entries only after the rm succeeds
        // so a transient FS error doesn't lose the streak.
        var deleted: [String] = []
        for uuid in toDelete {
            let ringURL = ringDirectoryURL
                .appendingPathComponent("\(uuid).ring", isDirectory: false)
            do {
                try FileManager.default.removeItem(at: ringURL)
                counters.removeValue(forKey: uuid)
                deleted.append(uuid)
            } catch {
                logger.warning("auto-GC: rm \(ringURL.path) err=\(error)")
            }
        }

        if !deleted.isEmpty {
            let joined = deleted.joined(separator: ",")
            logger.info("auto-GC: deleted \(deleted.count) stale orphan ring(s) at threshold=\(threshold): \(joined)")
        }
        if capped {
            logger.warning("auto-GC: deletion-per-launch cap (\(Self.gcMaxDeletionsPerLaunch)) hit — stopped early; remaining candidates will be picked up next launch")
        }

        writeGCCounters(counters)
    }

    private static func readGCCounters() -> [String: Int] {
        let url = gcCounterURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: Int].self, from: data)
        } catch {
            logger.warning("auto-GC: gc-counter.json corrupt, resetting (err=\(error))")
            try? FileManager.default.removeItem(at: url)
            return [:]
        }
    }

    private static func writeGCCounters(_ counters: [String: Int]) {
        let url = gcCounterURL
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        } catch {
            logger.warning("auto-GC: mkdir \(dir.path) err=\(error)")
            return
        }

        if counters.isEmpty {
            // Nothing to track — remove the file so a future corrupt-empty
            // read can't masquerade as state.
            try? FileManager.default.removeItem(at: url)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(counters)
        } catch {
            logger.warning("auto-GC: encode err=\(error)")
            return
        }

        let tmp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: [.atomic])
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            logger.warning("auto-GC: write \(url.path) err=\(error)")
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    /// Pure decision: which rings to reclaim given the previous-refresh live set,
    /// the current live set, and whether the app is terminating. Surfaces present
    /// last refresh but gone now are real closes. While terminating, reclaim
    /// nothing (preserve for cold-restore). Extracted for unit testing.
    static func ringsToReclaim(
        previousLive: Set<String>,
        currentLive: Set<String>,
        isTerminating: Bool
    ) -> Set<String> {
        guard !isTerminating else { return [] }
        return previousLive.subtracting(currentLive)
    }

    /// Best-effort deletion of the ring files for `uuids` (surfaces closed this
    /// session). Logs failures; a missing file is not an error. Only ever called
    /// from `refreshFromCurrentControllers` with session-live UUIDs, so it can
    /// never touch prior-session content that has not been seen this run.
    private static func deleteRings(_ uuids: Set<String>) {
        guard !uuids.isEmpty else { return }
        var removed = 0
        for uuid in uuids {
            let url = ringDirectoryURL.appendingPathComponent("\(uuid).ring", isDirectory: false)
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch CocoaError.fileNoSuchFile {
                // Already gone (manual rm, prior GC) — nothing to do.
            } catch {
                logger.warning("session-manifest: reclaim-on-close rm \(url.path) err=\(error)")
            }
        }
        if removed > 0 {
            logger.info("session-manifest: reclaimed \(removed) ring(s) on surface close")
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
