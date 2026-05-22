# Session-restore manifest — gap closure for P7 Phase B2

Started 2026-05-21 during review of commit `842766c51` (P7 Phase B2 auto-replay).

## Why this file exists

Phase B2 ships PTY-byte persistence (`~/.void/sessions/by-uuid/<uuid>.ring`)
plus an auto-replay path on `Termio.init`. The replay path is **per-UUID
best-effort**: it just takes the UUID handed in by Swift and tries to open the
matching ring. If that UUID didn't make it onto disk in the prior session's
SplitTree (because AppKit's `NSWindowRestoration` flush is async/batched while
the ring write is per-byte synchronous), the ring becomes a silent orphan.

This file tracks the patch that closes that gap and what's left.

## Gap analysis

| # | Gap | Where | Severity |
|---|-----|-------|----------|
| 1 | Ring↔SplitTree flush rate mismatch | `Termio.processOutput` is sync per byte; `invalidateRestorableState()` is AppKit-batched async | **High** — silent loss on crash between tree change and flush |
| 2 | No matching validation at replay | `src/termio/Termio.zig:329-382` blindly opens ring at UUID, no timestamp / epoch / live-set check | Medium |
| 3 | Orphan rings accumulate forever | `src/termio/Termio.zig:421-425` intentionally never deletes; README:282 says `rm -rf` is the only cleanup | Medium |
| 4 | No "last known session" anchor | No top-level manifest; AppKit's per-window restorable state is the only source of truth | **High** — root cause of #1 |
| 5 | Recovery silent to the user | `tool/void-session-replay.sh` exists but no startup-time visibility | Low — observability |
| 6 | `window-save-state = never` strands every ring | `TerminalRestorable.swift:101-104` short-circuits decode | Medium |

## Patch v1 — synchronous manifest + launch-time triage (this PR)

### Design

```
   write side (every surfaceTreeDidChange)        read side (app launch)
   ────────────────────────────────────           ──────────────────────────
   BaseTerminalController.didSet                  applicationWillFinishLaunching
      → SessionManifest.refreshFromCurrent…          → SessionManifest.captureFromDisk()
            ↓ next runloop tick                            ↓ in-memory previousSession
        atomic .tmp + rename                         applicationDidFinishLaunching + 500ms
        ~/.void/sessions/last.json                     → SessionManifest.triage(restored)
                                                            → log recovered/topology-lost/stale-orphans
```

### Files

| File | Change |
|------|--------|
| `macos/Sources/Features/Terminal/SessionManifest.swift` | **NEW** — schema, write/read/triage |
| `macos/Sources/Features/Terminal/BaseTerminalController.swift` | Hook `surfaceTreeDidChange` → `refreshFromCurrentControllers()` |
| `macos/Sources/App/macOS/AppDelegate.swift` | `applicationWillFinishLaunching` captureFromDisk; `applicationDidFinishLaunching` triage after 500ms |

### Manifest schema

```json
{
  "version": 1,
  "epochNs": 1779338814636365056,
  "surfaces": ["UUID-1", "UUID-2", ...]
}
```

Flat list of UUIDs. No per-window grouping yet (kept minimal — the dangerous
case is "any UUID present in prev but absent in restored").

### Triage sets

| Set | Meaning | Action in v1 |
|-----|---------|--------------|
| `prev ∩ restored` | recovered cleanly | log count |
| `prev - restored` | AppKit flush lag loss — ring exists, topology gone | **warning log** (this is the silent-loss bug) |
| `disk - prev` | from sessions older than the last one | log count, no GC yet |

### Threading notes

- `refreshFromCurrentControllers()` is called from `surfaceTreeDidChange`
  which runs on the main thread (SwiftUI `@Published` didSet). The actual
  write is deferred one runloop tick via `DispatchQueue.main.async` so the
  controller is attached to NSApp.windows by the time we enumerate (during
  `BaseTerminalController.init`, the controller has `super.init(window: nil)`
  and isn't yet enumerable). `refreshScheduled` flag coalesces rapid-fire
  changes within a single tick.
- Triage uses `TerminalController.all` which walks `NSApp.windows` — fine to
  call from main thread, fine after the 500ms delay (restoration completion
  handlers fire inline during launch).

See `PLAN.log.md` for the 2026-05-21 verification snapshot that confirmed
this triage exposes the prior silent-loss failure mode.

## What's left

Ordered by leverage:

1. **Surface the failure in-app** (was Gap #5)
   - First-window toolbar badge: "2 prior sessions could not be auto-restored"
   - Click → table of orphan UUIDs with cwd-from-ring-tail preview + "Open in new tab" / "Discard"
   - Probably lives next to the `void-session-replay.sh` flow

2. **Ring header epoch** (was Gap #2)
   - Add `last_msync_ns` to `PersistRing` header so triage can sort orphans by recency
   - Lets the in-app UI distinguish "from 5 minutes ago" vs "from a week ago"

3. **Per-window grouping in manifest** (extension of #4)
   - Promote schema to `windows: [{tab_id, uuids: [...]}]`
   - Lets relaunch reconstruct topology when AppKit's state was lost entirely
   - Useful for `window-save-state = never` (Gap #6)

4. **Auto-GC for unambiguous orphans** (was Gap #3)
   - After N launches where a UUID stays in `disk - prev`, delete its ring
   - Conservative threshold (3+ launches? configurable?)
   - **Risky** — don't touch until #1 is in place so users have a recovery path

5. **Validate ring on open** (was Gap #2 part 2)
   - Compare ring's last-msync time vs manifest epoch — flag if drift > 5s
   - Goes in `Termio.init` replay path

## Open questions

- **Should `applicationDidFinishLaunching` triage delay (currently 500ms) be
  driven by something more deterministic?** Maybe a one-shot observer on
  `NSWindow.didBecomeKeyNotification` for the first restored window. The 500ms
  is a guess; on slow restores it could fire before all controllers settle and
  over-report topology loss.

- **Manifest write granularity** — currently every `surfaceTreeDidChange` (so
  every split add/remove, tab close, etc.). For very rapid sequences (script
  spawns N panes) this is N writes within a tick — the coalesce flag handles
  it but worth profiling under heavy load. Per-byte cost is negligible
  compared to the rings themselves.

- **`previousSession` is `static var`** — fine for the single-app-instance
  case but if we ever support multi-instance (e.g. CLI-spawn with `--new`),
  re-think.

## Related work / context

- Phase B1: ring persistence (`46a0cbff2..` lineage, landed 2026-04-29 per
  commit msg of B2)
- Phase B2: replay on restart (commit `842766c51`, this PR's parent)
- Phase B3 (not started): hot-reattach to a daemon-held session — referenced
  in `Termio.zig:421-425` deinit comment

Cross-host bootstrap notes (mini, build-env reproduction) and the v1 decision
log live in `PLAN.log.md`.
