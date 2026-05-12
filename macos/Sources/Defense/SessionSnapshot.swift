import Foundation
import OSLog

/// D3 — atomic session snapshot writer.
///
/// The host supplies a `SnapshotProvider` that returns the current SnapshotV1
/// (windows / tabs / scrollback tail). `SessionSnapshot` handles serialization,
/// atomic write, `current.json` symlink update, and retention.
struct SnapshotV1: Codable {
    struct TabState: Codable {
        var title: String
        var cwd: String?
        var shell: String?
        var argv: [String]
        var envDiff: [String: String]
        var scrollbackTailGz: Data?
        var cursorRow: Int
        var cursorCol: Int
        var cols: Int
        var rows: Int
    }

    struct WindowState: Codable {
        var frame: [Double]   // x, y, w, h
        var tabs: [TabState]
    }

    enum Reason: String, Codable {
        case periodic, pressureWarn, pressureCritical, wsDegraded, shutdown, crash
    }

    var version: Int = 1
    var savedAt: Date
    var reason: Reason
    var windows: [WindowState]
}

typealias SnapshotProvider = () -> SnapshotV1

final class SessionSnapshot {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dancinlab.void",
        category: "Defense.Snapshot"
    )

    /// `~/Library/Application Support/com.dancinlab.void/sessions/`
    let dir: URL
    let retention: Int
    private let queue = DispatchQueue(
        label: "com.dancinlab.void.defense.snapshot",
        qos: .utility
    )
    private let provider: SnapshotProvider

    /// Min interval between non-critical saves; collapses bursts into one write.
    private let debounceInterval: TimeInterval = 6
    private var lastSaveAt: Date = .distantPast

    init(
        provider: @escaping SnapshotProvider,
        directory: URL? = nil,
        retention: Int = 6
    ) {
        self.provider = provider
        self.retention = retention
        if let directory {
            self.dir = directory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            self.dir = appSupport
                .appendingPathComponent("com.dancinlab.void", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
    }

    /// Run once at app launch.
    func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
    }

    /// Trigger a save. `force=true` skips the debounce — use it for
    /// `pressureCritical`, `wsDegraded`, `shutdown`, and `crash`.
    @discardableResult
    func save(reason: SnapshotV1.Reason, force: Bool = false) -> URL? {
        let now = Date()
        if !force, now.timeIntervalSince(lastSaveAt) < debounceInterval {
            return nil
        }
        lastSaveAt = now

        var snap = provider()
        snap.savedAt = now
        snap.reason = reason

        return queue.sync {
            do {
                ensureDirectory()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(snap)

                let stamp = SessionSnapshot.iso8601Compact(now)
                let target = dir.appendingPathComponent("\(stamp).json")
                try data.write(to: target, options: [.atomic])

                updateCurrentSymlink(to: target)
                rotate()
                logger.notice("snapshot saved reason=\(reason.rawValue, privacy: .public) bytes=\(data.count)")
                return target
            } catch {
                logger.error("snapshot save failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private func updateCurrentSymlink(to target: URL) {
        let link = dir.appendingPathComponent("current.json")
        let fm = FileManager.default
        try? fm.removeItem(at: link)
        try? fm.createSymbolicLink(
            at: link,
            withDestinationURL: URL(fileURLWithPath: target.lastPathComponent)
        )
    }

    private func rotate() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let snaps = entries
            .filter { $0.lastPathComponent != "current.json" && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }

        guard snaps.count > retention else { return }
        for old in snaps[retention...] {
            try? fm.removeItem(at: old)
        }
    }

    /// Best-effort load of the most recent snapshot (for restore flow).
    func loadCurrent() -> SnapshotV1? {
        let link = dir.appendingPathComponent("current.json")
        guard let data = try? Data(contentsOf: link) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SnapshotV1.self, from: data)
    }

    private static func iso8601Compact(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
