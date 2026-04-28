// P7 Phase B1-prep: structural session persistence (grid + SplitTree).
//
// One SessionPersistManager per window. Writes are atomic (`*.tmp` +
// `rename(2)`) so a crash mid-write never leaves a corrupted state file.
// Triggered by structural changes only (split create/destroy, tab open/
// close, grid slot move) — typical interactive rate is ≤ 1/sec, so the
// O(file rewrite) cost is negligible.
//
// PTY byte-stream persistence is a separate concern handled by
// `PersistRing.zig` on the Zig side (per-pane mmap'd ring).
//
// ## Status
//
// Phase B1-prep: skeleton + interface only. TerminalController hook
// (call `persist(splitTree:)` on every change) is Phase B1-impl,
// separate commit. Restore path (`load(windowID:)` reading and
// reconstructing) is Phase B2.
//
// ## Disk layout
//
// ```
// ~/.void/sessions/
//   windows/
//     <window-id>/
//       meta.json          // window pos/size/fullscreen/grid topology
//       split.json         // SplitTree (Codable — already wired in
//                          //            macos/Sources/Features/Splits/SplitTree.swift)
//       tabs/
//         <tab-id>/
//           split.json     // per-tab SplitTree
//           panes/
//             <pane-id>/
//               meta.json  // cwd, command, env_hash, started_at
//               bytes.ring // managed by PersistRing.zig (Zig side)
// ```
//
// ## Origin
//
// 2026-04-29 conversation — user requested void abnormal-termination +
// macOS-crash recovery (full grid + screen-content restore on relaunch).
// Hybrid policy: structural changes flush immediately (this file's job),
// PTY bytes flush per-read via mmap ring (Zig side), screen state is
// recomputable from byte stream on replay.
//
// See `docs/design/sighup-resistant-session.md` Phase B1 section.

import Foundation

/// Per-window session persistence manager.
///
/// Writes structural state (grid + SplitTree + window geometry) to
/// `~/.void/sessions/windows/<windowID>/` atomically on every change.
/// PTY byte streams are persisted separately by Zig-side `PersistRing`
/// — this manager does not touch them.
///
/// Thread-safety: all public methods are safe to call from the main
/// thread. The atomic write itself releases its temporary fd before
/// `rename(2)` so concurrent reads from the restore path always see
/// either the previous state or the new state, never partial.
final class SessionPersistManager {

    /// Stable identifier for this window's persistence root. Caller
    /// supplies (typically `String(window.windowNumber)` or a UUID
    /// scoped to the window's lifetime within a single launch — Phase
    /// B2 must decide whether IDs survive across launches).
    let windowID: String

    /// Root directory for this window. Created lazily on first write.
    private let rootURL: URL

    /// Single FileManager instance — cheaper than re-instantiating.
    private let fm = FileManager.default

    init(windowID: String) {
        self.windowID = windowID
        let home = fm.homeDirectoryForCurrentUser
        self.rootURL = home
            .appendingPathComponent(".void", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("windows", isDirectory: true)
            .appendingPathComponent(windowID, isDirectory: true)
    }

    // MARK: - Public API (Phase B1-impl will wire callers)

    /// Persist a generic Codable payload to `<root>/<filename>`.
    /// Atomic via `*.tmp` + `rename(2)`.
    ///
    /// `T` is typically `SplitTree<...>` or a small POD struct. Caller
    /// is responsible for encoding scope (window-level vs tab-level).
    func persist<T: Encodable>(_ value: T, to filename: String) throws {
        try ensureRoot()
        let target = rootURL.appendingPathComponent(filename)
        let tmp = rootURL.appendingPathComponent(filename + ".tmp")

        let data = try JSONEncoder().encode(value)
        try data.write(to: tmp, options: .atomic)
        // `Data.write(.atomic)` itself uses a temp + rename, but we add
        // an extra rename so consumers that watch by name see exactly
        // one transition per write rather than the brief tmp-suffix
        // window from `.atomic`.
        _ = try? fm.removeItem(at: target)
        try fm.moveItem(at: tmp, to: target)
    }

    /// Load a previously-persisted Codable from `<root>/<filename>`.
    /// Returns nil if the file does not exist (fresh start).
    func load<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        let target = rootURL.appendingPathComponent(filename)
        guard fm.fileExists(atPath: target.path) else { return nil }
        let data = try Data(contentsOf: target)
        return try JSONDecoder().decode(type, from: data)
    }

    /// List all persisted window IDs across launches. Used by the
    /// startup-restore path to enumerate which windows to reconstruct.
    static func enumeratePersistedWindows() throws -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let windowsRoot = home
            .appendingPathComponent(".void", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("windows", isDirectory: true)

        guard fm.fileExists(atPath: windowsRoot.path) else { return [] }
        let entries = try fm.contentsOfDirectory(atPath: windowsRoot.path)
        return entries.filter { !$0.hasPrefix(".") }
    }

    /// Remove this window's persistence entirely. Called on explicit
    /// window-close (Cmd+Shift+W with confirmation) so the window does
    /// not get resurrected on next launch.
    func purge() throws {
        guard fm.fileExists(atPath: rootURL.path) else { return }
        try fm.removeItem(at: rootURL)
    }

    // MARK: - Private

    private func ensureRoot() throws {
        try fm.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }
}
