# P7 — Session Preservation Across Abnormal Termination

Status: in-progress (PTY byte preservation + manual recovery CLI landed 2026-04-29; auto-replay is Phase B2)
Created: 2026-04-28; honest scope reset: 2026-04-29
Origin: 2026-04-28 user requirement — *"void가 비정상 종료시 다시 실행 시 그리드 + 터미널 내용 그대로 복구, macOS 크래시 후 재실행 포함"*.

## What the user wants

Two failure modes, one recovery experience:

| Scenario | Event | Restore goal on relaunch |
|---|---|---|
| **A** (void only dies) | segfault, OOM, jetsam SIGKILL | grid + terminal content as it was |
| **B** (macOS dies) | kernel panic, hard shutdown, power loss | same |

## Existing infrastructure (already shipped, no new code)

`macos/Sources/Features/Terminal/TerminalRestorable.swift` (193 LoC, pre-existing) is the
canonical macOS `NSWindowRestoration` integration. It encodes per window:

- `surfaceTree: SplitTree<VD.SurfaceView>` — full split topology (the *grid*)
- `focusedSurface: String?` — focused-pane UUID
- `effectiveFullscreenMode: FullscreenMode?`
- `tabColor: TerminalTabColor`
- `titleOverride: String?`

`TerminalWindowRestoration.restoreWindow` decodes this on relaunch and reconstructs
the controller with the exact same `SplitTree`. The `SurfaceView`'s UUID survives the
`Codable` round-trip (see `OSSurfaceView.swift:9` `let id: UUID` + the `init(id:frame:)`
init at line 61).

Activation is a single config line:

```
window-save-state = always
```

(`default` works only for force-quit + system-wide setting; `always` saves on every
exit including crash via AppKit's autosaved restorable state.) See `windowSaveState`
config docs in `Config.zig` and the `NSQuitAlwaysKeepsWindows` switch in
`AppDelegate.swift:764`.

What this gives the user **for free**, no new code:

- Window position, size, fullscreen mode
- Grid + SplitTree topology with correct ratios
- Focused pane restored
- Tab color and title overrides

What this does NOT give:

- PTY scrollback / live screen content (each restored surface gets a fresh shell)
- cwd preservation (each restored surface starts in default cwd)

## What new code we ship

The only gap above is **PTY content**. Two halves:

### Half 1 — write bytes to disk during the session (landed 2026-04-29)

`src/termio/PersistRing.zig` — mmap'd ring buffer per `Termio` instance.

- File path: `~/.void/sessions/by-pid/<pid>/<termio-addr-hex>.ring`
- Default capacity: 4 MB per ring (~100k rows of 80×100)
- Header: `PVER` magic (4B) + write_offset (u64 LE) + generation (u64 LE) + reserved
- Append in `Termio.processOutput` (read path) — `~0 µs memcpy`, no contention
- 1-second `msync(MS_ASYNC)` timer in `Exec.threadEnter` → bounds Scenario B loss to ≤ 1s
- Opt-in: `persist-bytes-mmap = true` in config

Data-loss bounds on the disk file:

| Scenario | Bound | Mechanism |
|---|---|---|
| A (void crash, mac up) | < 16 KB (one in-flight read) | mmap MAP_SHARED page cache survives process death |
| B (mac panic / power loss) | ≤ 1 second | msync(MS_ASYNC) every 1s + kernel periodic flush |

### Half 2a — manual recovery CLI (landed 2026-04-29)

`tool/void-session-replay.sh` — POSIX shell + python3 + xxd + dd.

```sh
void-session-replay.sh --list           # enumerate ring files
void-session-replay.sh --latest         # dump most recent ring's bytes
void-session-replay.sh --all            # dump every ring
void-session-replay.sh <path-to-ring>   # dump one
```

The bytes are *recovered* but go to stdout, not into a freshly-spawned void surface.
Pipe to `less -R`, `cat`, or save to a file.

### Half 2b — automatic replay on restore (Phase B2, NOT yet landed)

Required scope (~150 LoC):

- Add `surface_uuid: ?UUID` to `VD.SurfaceConfiguration` (Swift)
- Extend the C ABI surface-init struct with the UUID field
- `Surface.zig` reads the UUID, passes through `Termio.Options`
- `Termio.zig` uses UUID-based ring path: `~/.void/sessions/by-uuid/<uuid>.ring`
  (replaces the current ephemeral `<addr>.ring` path)
- `Termio.init` checks if a ring already exists at that path; if so opens RDONLY,
  calls `replay()`, then `processOutput(replayed_bytes)` BEFORE the read thread starts
- `TerminalWindowRestoration` already preserves the UUID via SplitTree Codable —
  no Swift restoration changes needed

Phase B2 is the "auto-restore" piece. Until landed, half 2a (`void-session-replay.sh`)
is the manual recovery path.

## Retired / over-coded — removed 2026-04-29

These were briefly landed during the 2026-04-28 → 04-29 work and removed in cleanup
after honest measurement showed they were either redundant with existing infra or
solved a different problem from the one stated:

- **Phase A1 detach-on-close** (`@"detach-on-close"` config + `Subprocess.stop()`
  short-circuit + Surface.zig wire). Addressed window-close cascade-kill (different
  axis from crash recovery), and even within its own scope was non-functional alone
  (`Subprocess.stop()` skips our explicit `killpg`, but `Subprocess.deinit` still
  closes the master pty fd which causes the kernel to SIGHUP the controlling-tty
  group). True window-close-survival requires the DetachedSessionPool ("Phase A2"
  in the original sketch) which is a separate larger work item — not part of this
  P7 axis.
- **`SessionPersistManager.swift`** scaffolding. Redundant with `TerminalRestorable`
  which already does the SplitTree atomic write via NSCoder.
- **`@"persist-grid-on-change"` config**. Dead — no callers. The grid persistence
  it intended was already done by `TerminalRestorable` + `window-save-state`.

If a future phase needs detach-on-close (different axis: "preserve child across
*window close*", not "across *crash*"), it can reintroduce the field along with the
required DetachedSessionPool implementation. The bare opt-in flag without the pool
served no purpose.

## Falsifiers (raw 71)

- F-1: 30d post — `persist-bytes-mmap = true` adoption < 0.10 of users who hit a
  crash → feature ineffective, retire OR redesign UX
- F-2: ring file write rate observed > 5% CPU → memcpy path is wrong, optimize OR
  retire
- F-3: msync 1s tick reproducibly OOMs jetsam → reduce cap to 1MB OR retire
- F-4: `void-session-replay.sh --latest` produces garbage on a real void session →
  PVER header / write_offset logic broken
- F-5: ring file accumulates without bound across many sessions → add purge policy
  (currently absent, manual `rm -rf ~/.void/sessions` recommended)
