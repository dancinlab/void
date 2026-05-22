# PLAN.log — session-restore manifest history

Companion log to `PLAN.md`. Dated events, verification snapshots, and decision
records for the P7 Phase B2 gap-closure work.

## Verification (2026-05-21, on commit at time of patch landing)

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
