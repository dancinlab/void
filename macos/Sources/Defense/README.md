# VOID Defense Layer — MVP (D1a + D3 + D5)

Code-side companion to
`hexa-lang/doc/superpowers/specs/2026-05-11-void-defense-design.md`.

This MVP covers three layers from the design spec:

| Layer | File | Purpose |
|---|---|---|
| D1a | `PressureMonitor.swift`     | macOS memory pressure source (warn / critical) |
| D3  | `SessionSnapshot.swift`     | Atomic snapshot writer + retention + restore loader |
| D5  | `CrashCapture.swift`        | Uncaught exception + signal handlers, async-signal-safe bundle |
| —   | `DefenseCoordinator.swift`  | Wires the three together |

**Not included in MVP** (deferred per spec phase plan):
D1b WindowServer health, D2 RSS cap, D4 spawn throttle, D6 external watchdog.

## Files in this directory

```
Defense/
├── PressureMonitor.swift       109 lines
├── SessionSnapshot.swift       183 lines
├── CrashCapture.swift          181 lines
├── DefenseCoordinator.swift     86 lines
└── README.md                    (this file)
```

The four Swift files parse cleanly individually and as a single module
(`xcrun swiftc -parse *.swift`).

## Adding to the Xcode project

The MVP cannot be exercised until the files are members of the Void macOS
target. Open `void/macos/Void.xcodeproj` and:

1. **Add the folder reference**
   File → Add Files to "Void"... → select `Sources/Defense/`,
   choose **"Create groups"** (not folder reference), make sure
   the Void target is checked.
2. **Verify target membership** for all 4 `.swift` files in the file inspector.
3. **No new entitlements required** — Defense uses only Foundation + Darwin
   APIs already permitted to a sandboxed terminal app.
4. **No bridging-header changes required** — `Darwin` already exposes
   `sigaction`, `signal`, `backtrace`, `backtrace_symbols_fd`, `link`,
   `mkdir`, `open`, `time`, `snprintf`.
5. Build once. Cross-file references (e.g. `SnapshotProvider` in
   `DefenseCoordinator`) will resolve as soon as the files share a target.

## Wiring into AppDelegate

In `Sources/App/macOS/AppDelegate.swift`:

```swift
private var defense: DefenseCoordinator?

func applicationDidFinishLaunching(_ notification: Notification) {
    // ... existing setup ...

    let coordinator = DefenseCoordinator(snapshotProvider: { [weak self] in
        self?.collectSnapshot() ?? SnapshotV1(
            savedAt: Date(), reason: .periodic, windows: []
        )
    })
    coordinator.onWarning  = { [weak self] in self?.trimCachesForWarning()  }
    coordinator.onCritical = { [weak self] in self?.trimCachesForCritical() }
    coordinator.start()
    self.defense = coordinator
}

func applicationWillTerminate(_ notification: Notification) {
    defense?.stopForShutdown()
}

private func collectSnapshot() -> SnapshotV1 {
    // Walk window controllers → tabs → terminal surfaces.
    // Caller is on the snapshot queue; do NOT touch UIKit/AppKit state
    // synchronously from there — read from a thread-safe model snapshot.
    let windows: [SnapshotV1.WindowState] = NSApp.windows.compactMap { /* ... */ }
    return SnapshotV1(savedAt: Date(), reason: .periodic, windows: windows)
}
```

`collectSnapshot()` is the only host-specific glue. Everything else is generic.

## What lands on disk

```
~/Library/Application Support/com.dancinlab.void/sessions/
├── current.json                   # symlink → most recent snapshot
└── 20260511T001200Z.json          # one per save event, max 6 retained

~/Library/Logs/com.dancinlab.void/crashes/
└── 1715378150-sig11/              # signal-handler bundles
    ├── stack.txt                  # backtrace_symbols_fd output
    └── snapshot.json              # hardlink of the last snapshot
```

The Obj-C exception path (separate from the POSIX signal path) writes
ISO-8601 named bundles instead, since it can use Foundation safely.

## Restore (still TODO in this MVP)

`SessionSnapshot.loadCurrent()` returns the parsed `SnapshotV1?`. The host
must implement the actual tab/window restore — out of scope for the
defense layer because it depends on Void's own surface controllers.

A reasonable launch path:

```swift
if let snap = coordinator.snapshot.loadCurrent(),
   snap.reason == .pressureCritical || snap.reason == .crash || snap.reason == .wsDegraded,
   Date().timeIntervalSince(snap.savedAt) < 24 * 3600 {
    promptUserToRestore(snap)
}
```

## Manual testing

```sh
# D1a — fire warning + critical
sudo memory_pressure -l warn
sudo memory_pressure -l critical

# D3 — verify snapshot lands
ls -lt ~/Library/Application\ Support/com.dancinlab.void/sessions/

# D5 — trigger SIGSEGV from a debug menu item or LLDB:
#   (lldb) p ((*(volatile int *)0))
ls -lt ~/Library/Logs/com.dancinlab.void/crashes/
```

`memory_pressure(8)` is Apple's official tool for D1a testing — DO NOT
artificially balloon memory. `kill -SEGV` from the outside also works for
D5 if you don't mind losing the actual stack.

## Signal-safety contract (important)

The POSIX signal path in `CrashCapture` runs on the faulting thread with a
possibly-corrupt stack. It uses only:

- `time(2)`, `mkdir(2)`, `open(2)`, `close(2)`, `write(2)` — POSIX async-signal-safe
- `link(2)` — POSIX async-signal-safe
- `backtrace(3)`, `backtrace_symbols_fd(3)` — Apple-documented async-signal-safe
- `snprintf(3)` — POSIX async-signal-safe (XSI)
- `Array.withUnsafeBufferPointer` on a pre-allocated `[CChar]` —
  no Swift heap allocation; just exposes the existing buffer

Anything that allocates (Swift `String` operations, `URL`, `FileManager`,
`Logger`) is **only** used in the Obj-C exception path or in normal
`install()` / `setCurrentSnapshotPath()` setup paths.

The `entered` re-entry guard ensures that if the safe path *itself*
crashes, we hand straight back to `SIG_DFL` without looping.
