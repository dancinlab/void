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

## Verification (2026-05-21, on this commit)

```
$ ls /Users/ghost/.void/sessions/by-uuid/ | wc -l
11                              # 11 ring files on disk before patch
```

After launching the patched build with no prior manifest:

```
$ cat /Users/ghost/.void/sessions/last.json
{
  "epochNs": 1779338796087915008,
  "surfaces": ["983CBA2F-C3D7-4749-A689-00420BFBA322"],
  "version": 1
}
```

After Cmd+T (new tab), quit, relaunch — log shows the triage:

```
session-manifest: captured prior session with 2 surface(s)
session-manifest triage: recovered=0 topology-lost=2 stale-orphans=11
session-manifest: ring files exist for UUIDs not restored by AppKit — content stranded.
```

This is **exactly the failure mode the manifest was built to expose**: the
prior session had 2 live surfaces, AppKit restored 0 (likely because
`window-save-state` is not set to "always" in this user's config — see Gap #6),
and now the manifest tells us 2 UUIDs have rings sitting on disk with no UI
bound to them. Without this manifest, those would have been silent losses.

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

## Cross-host build environment (mini, 2026-05-21)

Reproducing the hang on a second host (`mini`, Mac mini) surfaced the full
list of bootstrap steps needed beyond a fresh checkout. Recording here so
the next person doesn't have to rediscover them.

### Sequence that worked

1. **OS upgrade to match SDK**. mini was on macOS 26.4 but Xcode 26.5 (from
   `xcodes install 26.5`) ships SDK 26.5. zig 0.15.2's host target detection
   sets `aarch64-macos.26.4...26.4-none` from the OS, then chokes on tbd
   symbol resolution against the 26.5 SDK. Upgrade via
   `softwareupdate -ia -R --agree-to-license --user <user> --stdinpass` —
   Apple Silicon's Volume Owner check needs the local password via stdin
   even when sudo is passwordless.
2. **Xcode via `xcodes install 26.5`**. App Store flow is GUI-bound and
   Screen Sharing tripped a permissions wall on the headless mini; xcodes
   over `ssh -t` works as long as the Apple ID + 2FA can be answered live.
3. **Homebrew, not ziglang.org tarball, for zig**. Same nominal 0.15.2 but
   the Homebrew bottle (`zig@0.15`) and the official ziglang.org tarball
   produce different binaries — and the ziglang.org one's bundled MachO
   linker fails to resolve libSystem symbols on this mini (works on the
   local box, root cause unidentified). Homebrew bottle links cleanly.
   Symlink it into the repo's expected vendor path:
   `ln -sf /opt/homebrew/Cellar/zig@0.15/0.15.2/bin/zig vendor/zig-0.15.2/bin/zig`.
4. **`brew install gettext`**. Locale builds invoke `msgfmt`; mini's CLT
   doesn't ship it. brew's gettext is keg-only by default but the build
   only needs `msgfmt` reachable via PATH from the brew shellenv.
5. **`sudo xcodebuild -downloadComponent MetalToolchain`**. macOS 26's
   Xcode ships without the metal compiler — first invocation prompts for
   it. Asset lands in `/var/run/com.apple.security.cryptexd/mnt/`.
6. **`TOOLCHAINS=com.apple.MetalToolchain` env var at build time**. With
   the Metal toolchain installed but not registered as XcodeDefault's
   metal, `xcrun -sdk macosx metal` still falls through to the
   "missing toolchain" wrapper. Explicit `TOOLCHAINS=` (or
   `xcrun -toolchain com.apple.MetalToolchain ...`) routes to the cryptex
   path. Without this, the xcframework build fails near the end of an
   otherwise-successful run (long error chain — easy to miss).

### Final build command on mini

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
export TOOLCHAINS=com.apple.MetalToolchain
cd ~/core/void
vendor/zig-0.15.2/bin/zig build -Demit-macos-app -Doptimize=ReleaseFast
```

Produces `macos/build/ReleaseLocal/Void.app` (60 MB, binary 44 MB).
Symbol check: `nm Void.app/Contents/MacOS/void | grep -c SessionManifest`
returned 99 — patch is in.

### Things that did NOT work and why (so we don't re-try)

- Plain `xcodebuild -downloadComponent MetalToolchain` followed by
  re-build: toolchain downloads to cryptex but xcrun's `metal` wrapper
  doesn't pick it up without `TOOLCHAINS=...`.
- Setting `SDKROOT` and/or `MACOSX_DEPLOYMENT_TARGET` to bridge the OS
  ↔ SDK version gap: zig's `build_zcu.o` is compiled with the host's
  native target before the project options apply, so it ignored both.
- Passing `-Dtarget=aarch64-macos.26.5` to `zig build`: same reason —
  the project compiles fine with this, but the build script (build.zig
  itself) still uses native and fails to link.
- `tar -xzf zig.tar.xz` of the brew-Cellar zig from local copied to
  mini: brew's zig links against `/opt/homebrew/opt/llvm@20/lib/...`
  which isn't on mini.

### Follow-up for `pool init`

The `no-sleep` feature (commit `6a447b4`, [README](README.md)) is in.
Worth adding follow-ups when convenient:
- **`brew-bootstrap`** — install Homebrew if missing. Triggered by the
  tailscale feature already needing brew on macOS, but a dedicated step
  would make the dependency explicit.
- **`xcode-cli`** — `sudo xcodebuild -downloadComponent MetalToolchain`
  + ensure `xcode-select` points at full Xcode. Don't try to install
  Xcode itself (that needs Apple ID interactive auth).

## Decision log

- **2026-05-21** — Chose flat `surfaces: [uuid]` over `windows: [{...}]` for v1.
  Rationale: the dangerous case is "any prev UUID absent from restored", which
  doesn't need per-window structure. Per-window comes in #3 if we decide to
  reconstruct topology without AppKit.
- **2026-05-21** — Chose log-only (no GC, no UI) for v1. Rationale: observe
  the failure rate in the wild first; auto-GC without a user-visible recovery
  affordance would just be a different kind of silent loss.
- **2026-05-21** — Chose `DispatchQueue.main.async` over a synchronous write
  inside `surfaceTreeDidChange`. Rationale: during controller init, the
  window isn't attached to NSApp.windows yet — sync write would miss it. The
  one-tick deferral still wins the race against AppKit's flush by orders of
  magnitude.
