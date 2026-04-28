# P7 — SIGHUP-Resistant Session Preservation

Status: in-progress (Phase A1 landed 2026-04-29)
Created: 2026-04-29 (date-tick during draft)
Origin: 2026-04-28 user diagnosis — all claude TUIs in one iTerm window died simultaneously when the window closed. Root cause is generic to every PTY-spawning terminal emulator (void/ghostty included): `killpg(pgid, SIGHUP)` on surface close.

## Phase A1 — landed 2026-04-29 (config flag + stop() short-circuit)

**Scope**: opt-in scaffolding only. Default behavior unchanged.

**Files touched**:
- `src/config/Config.zig` — added `@"detach-on-close": bool = false` field with full docstring.
- `src/termio/Exec.zig` — added `detach_on_close` to `Exec.Config` (plumbing) and `Subprocess` (stored), populated in `Subprocess.init`, branched in `Subprocess.stop()` to skip `killCommand` and log a warning when set.
- `src/Surface.zig` — populated the new Exec.Config field from `config.@"detach-on-close"`.

**What it does today**:
- When the user sets `detach-on-close = true` in config, surface close logs `P7 detach-on-close: skipping killpg(SIGHUP) ...` and *does not* run our explicit `killpg`.
- The kernel can still SIGHUP the child once the master pty fd closes during `Subprocess.deinit` (because the master-side close drops the controlling tty's last reader). So Phase A1 alone does NOT yet preserve the child across window close — that's Phase A2's job.

**What Phase A1 IS useful for**:
- Foundation: config wiring, plumbing, stop()-path branch verified. Phase A2 plugs the actual fd-handoff into the same branch.
- Audit: turning on the flag and watching log output verifies the new code path fires for every surface close.
- Safety: default false, zero behavior change for existing users.

**Phase A2 next** (separate phase, sketch):
- App-level `DetachedSessionPool` (single per-app for v1, daemon for v2 cross-app).
- `Subprocess.detach()` method that hands master fd + pid + cwd to pool *before* `deinit` closes anything.
- Pool runs background read loop (discards bytes for v1 — Phase A3 adds ring buffer).
- New `void --attach <sid>` rebinds a fresh surface to a pool entry.

See `Open questions` section below for the 6 design decisions still required for Phase A2 promote.

## Phase B — abnormal-termination + macOS-crash recovery (B1-prep landed 2026-04-29)

Sister axis to Phase A. Where Phase A preserves **live processes** across surface close,
Phase B preserves **content + topology** across abnormal termination of void itself
(crash, OOM, jetsam SIGKILL) and across **macOS reboot/panic/power-loss**.

**Two scenarios:**

| Scenario | Event | Child PTY processes |
|---|---|---|
| **A** (void only dies) | segfault, OOM, jetsam SIGKILL | macOS still up — init can inherit children, but PTY master fd close → kernel SIGHUP → most TUIs die unless Phase A2 daemon holds the master fd |
| **B** (macOS dies) | kernel panic, hard shutdown, power loss | All processes die — no live recovery possible at all. Best we can do is restore content + respawn shells. |

**Hybrid persistence policy** (axis-2: WHEN to persist):

| Data | Policy | Cost | Loss in Scenario A | Loss in Scenario B |
|---|---|---|---|---|
| Grid topology + SplitTree | atomic write on every structural change (split/tab/grid/broadcast) | negligible (~1 event/sec typical) | 0 | 0 |
| Per-pane PTY byte stream | mmap'd ring, append in termio read path; `msync(MS_ASYNC)` every 1s | ~0 µs append, <0.1% CPU msync | < 16 KB (one read batch) | ≤ 1 second |
| Per-pane screen state (cursor, modes, alt-screen, scroll region) | 5s timer + dirty-mark | cheap | 5s — *recomputable* from byte stream replay | 5s — *recomputable* |

The screen-state column is "recomputable" because the byte stream IS the screen — replaying it
through a fresh terminal parser reproduces cursor/modes/etc. So Tier-A loss bound is the byte
stream loss, not the screen-state loss. Scenario B worst case ≤ 1 second of unrecorded PTY output.

**Disk layout** (matches PersistRing.zig + SessionPersistManager.swift):

```
~/.void/sessions/
  daemon.sock              ← Phase A2 daemon socket
  daemon.pid               ← daemon pid (raw 78 stale-lock pattern)
  windows/
    <window-id>/
      meta.json            ← window pos/size/fullscreen, grid topology
      split.json           ← top-level SplitTree (Codable already wired)
      tabs/
        <tab-id>/
          split.json       ← per-tab SplitTree
          panes/
            <pane-id>/
              meta.json    ← cwd, command, env_hash, started_at
              bytes.ring   ← mmap'd ring buffer (binary, 4 MB default)
```

**Restore flow** (Phase B2, planned):

```
void launch
  → SessionPersistManager.enumeratePersistedWindows()
  → for each window:
       restore window geometry + grid topology
       decode SplitTree (Codable, already works)
       for each pane:
         daemon has live pty.fd for this session id?  (Scenario A)
           YES: hot reattach via SCM_RIGHTS receive (Phase B3)
           NO:  cold respawn (Scenario B, or daemon down)
                ├─ spawn shell at saved cwd
                └─ replay bytes.ring to terminal screen for visual continuity
```

**Phase B sub-phases:**

| Phase | Scope | LoC est | Status |
|---|---|---|---|
| B1-prep | Config opt-in flags + PersistRing.zig skeleton + SessionPersistManager.swift skeleton | ~250 Zig + ~120 Swift | **landed 2026-04-29** |
| B1-impl | Wire PersistRing into termio read path + msync 1s timer + wire SessionPersistManager into TerminalController structural events | ~150 Zig + ~250 Swift | next |
| B2 | Cold-restart respawn — startup scan + grid/SplitTree decode + shell respawn at saved cwd + screen replay | ~500 Swift + ~150 Zig | after B1-impl |
| B3 | Hot reattach — daemon pool check, SCM_RIGHTS receive of live pty.fd, fallback to B2 respawn | ~250 Zig | needs A2 + B1-impl + B2 |

**Phase B1-prep landed 2026-04-29** (this commit):
- `src/config/Config.zig` — added `@"persist-grid-on-change": bool = false` + `@"persist-bytes-mmap": bool = false` opt-in fields
- `src/termio/PersistRing.zig` — new file, mmap'd ring buffer with `open` / `append` / `msyncAsync` / `replay` API. Two unit tests included (round-trip + wrap-around). Not yet wired into termio read path.
- `macos/Sources/Features/Terminal/SessionPersistManager.swift` — new file, atomic write helper for SplitTree + window metadata. `enumeratePersistedWindows()` already provided for B2 use. Not yet wired into TerminalController structural events.
- `.roadmap` P7 entry — added "phase b1-prep" sub-block.
- `docs/design/sighup-resistant-session.md` — this section.

Phase B1-prep is **scaffolding only** — no behavior change, no new code paths fire by default,
opt-in flags do nothing yet because nothing reads them. Phase B1-impl is the wiring commit.

## Problem

```
host terminal window close
  → controlling pts file descriptors closed
  → kernel posts SIGHUP to every process in the foreground process group
  → child shell forwards SIGHUP to its children
  → claude TUI (or any long-running TUI) receives SIGHUP, exits
```

In void specifically:

- `src/pty.zig:251-254` — child runs `setsid()` + `ioctl(slave, TIOCSCTTY)` so the slave PTY becomes its controlling terminal.
- `src/termio/Exec.zig:1156-1163` — surface close triggers `killpg(pgid, SIGHUP)` to terminate the child group cleanly.
- `src/termio/Exec.zig:1228` — same mechanism on explicit kill.

This is correct behavior for the default case (close window = stop work). But it makes long-running agent sessions, REPLs, ssh-mosh, and AI TUIs fragile against accidental window close, accidental Cmd+Q, host crash, terminal-emulator crash, etc.

## Solution: detach-on-close + session daemon + reattach

Per-surface opt-in flag `detach_on_close`. When set, surface close does **not** SIGHUP the child group. Instead:

1. PTY master fd + child pid + cwd + env + scrollback ring are handed off to a long-lived `void-session-daemon` process via `SCM_RIGHTS` (Unix domain socket fd-passing).
2. The session is registered at `~/.void/sessions/<sid>/` with metadata.
3. From a new void window, `void --attach <sid>` (or menu: Window → Attach Session…) creates a fresh surface bound to the existing PTY master fd. The child process does not notice — same controlling tty, same group, just a different window rendering it.

Live PTY survives across:
- void window close
- void app quit (daemon survives because it is a separate process)
- main void crash (daemon is independent)
- machine sleep (process is suspended/resumed normally)

Does NOT survive:
- explicit kill via Cmd+Shift+W with confirmation
- daemon idle-reap (default 48h with no reattach)
- machine reboot
- explicit `void --kill-session <sid>`

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ void main process (per window)                          │
│                                                         │
│  Surface ←→ Termio ←→ Exec.zig ←→ Pty (master fd)       │
│                              │                          │
│                              │ on close, if detach=true:│
│                              ▼                          │
│                         SCM_RIGHTS handoff              │
└────────────────────────────┬────────────────────────────┘
                             │ Unix domain socket
                             │ ~/.void/daemon.sock
                             ▼
┌─────────────────────────────────────────────────────────┐
│ void-session-daemon (separate process, lazy-spawned)    │
│                                                         │
│  SessionRegistry                                        │
│   └─ sid: pty.fd, pid, env, cwd, bytes.ring (2000 rows) │
│                                                         │
│  Read loop per session:                                  │
│   read(master_fd) → append to ring → no display         │
│                                                         │
│  Reattach loop:                                          │
│   accept new void surface → SCM_RIGHTS replay master_fd │
│   → flush ring → live read resumes                      │
└─────────────────────────────────────────────────────────┘
```

### Files to add (Zig)

- `src/termio/SessionDaemon.zig` — daemon main, registry, ring buffer, fd handoff
- `src/termio/SessionClient.zig` — main-process side of socket protocol
- `src/apprt/action.zig` — extend with `detach_session`, `attach_session`, `list_sessions`

### Files to modify (Zig)

- `src/termio/Exec.zig` — `Termio.deinit` checks `config.detach_on_close`; if true, SCM_RIGHTS handoff replaces SIGHUP
- `src/cli.zig` (or equivalent flag parsing) — add `--attach <sid>`, `--list-sessions`, `--kill-session <sid>`
- `src/config/Config.zig` — add `detach_on_close: bool = false` default

### Files to add/modify (Swift, macOS apprt)

- `BaseTerminalController` — Window menu items: Detach Session, Attach Session…, Sessions Manager…
- New `SessionsManagerController.swift` — list active sessions with cwd / age / pid

## Storage layout

```
~/.void/
  daemon.sock              ← Unix domain socket (created on daemon spawn)
  daemon.pid               ← daemon pid (raw 78 stale-lock pattern)
  sessions/
    <sid>/
      meta.json            ← { pid, cwd, env_hash, started_at, last_attach }
      bytes.ring           ← scrollback ring buffer (binary)
```

Session id format: `<host-short>-<pid-hex>-<rand6>` for human readability + collision resistance.

## Open questions (to settle before P7 active)

1. **Daemon lifecycle.** Lazy-spawn first detach + 48h idle-reap, OR always-on launchd plist?
   - **Lean lazy** — zero overhead when feature unused, plus respects raw 13 ban on per-repo automation config (no plist installed by repo).

2. **Daemon = same-binary thread vs separate process?**
   - **Separate process.** Survives main void crash (stronger guarantee). `void --daemon-fork` becomes daemon entry point.

3. **Composition with P2 scrollback restore.**
   - P2 serializes screen to NSCoder blob during graceful state save. P7 keeps PTY alive across save/restore. Attach path **skips** P2 replay because live PTY drives the screen directly. Only diverge when P7 is opted out OR session was killed.

4. **Cmd+Shift+W kill behavior.**
   - With confirmation dialog. Sends SIGHUP to child group + removes session registry entry.

5. **SSH peer disconnect over remote PTY.**
   - Out of scope for P7 v1. P7 covers local PTY only. Remote sessions need a different reconnect strategy (mosh-class).

6. **Race between handoff and child write.**
   - Daemon `read(master_fd)` only starts after `SCM_RIGHTS` confirmation. Main process drops master_fd reference after the send-msg. No window of double-read.

## Falsifiers (raw 71)

- F-1 30d post: `detach_on_close=true` opt-in adoption < 0.10 of long-running sessions → feature unused, retire OR redesign UX
- F-2 daemon crash recovery time > 5s (kid PTY zombied / orphaned) → architecture broken, rework SCM_RIGHTS path
- F-3 reattach byte-eq scrollback ring vs live screen mismatch > 5% → ring buffer logic broken, fix ring or expand cap
- F-4 ≥1 incident where daemon reaper killed an actively-attached session → reaper logic broken, immediate fix
- F-5 ≥1 incident where SCM_RIGHTS handoff produces leaked master_fd in main process (post-handoff fd not closed) → fd leak, fix close path

## Cross-references

- `.roadmap` P7 entry (this document is the design extension of that entry)
- `.roadmap` P2 — composes (P7 prevents, P2 restores after termination)
- `.roadmap` P4 — ai-native IO protocol benefits from detached sessions for agent handoff
- hive `raw 100` (kick canonical) + `raw 91` (honest C3) — this P7 was created via in-context omega-cycle fallback after nexus kick double-FAIL 2026-04-28 (witness-not-captured + all-claude-slots-exhausted)
- ghostty-org upstream — likely diverge candidate (ghostty-org has resisted built-in session-detach in past discussions, lean toward void-only feature per `.roadmap` P6)

## Next steps (when P7 promotes from todo → active)

1. Settle the 6 open questions above with implementation decisions.
2. Land `src/termio/SessionDaemon.zig` skeleton (registry + ring buffer, no fd-passing yet).
3. Land `src/termio/SessionClient.zig` + Unix socket protocol stub.
4. Wire `Exec.zig` close hook with `detach_on_close=false` default (no behavior change).
5. Implement SCM_RIGHTS fd-passing.
6. Wire `--attach` CLI flag (single-window proof of concept).
7. Add Swift menu items + SessionsManagerController.
8. Selftest fixtures: spawn → detach → process verified alive → attach from new window → byte-eq replay.
9. Land falsifier instrumentation (audit ledger entries on detach/attach/reap).
