# void

void is a terminal emulator written end-to-end in **hexa-lang** — it calls OS
APIs directly through hexa `extern fn` FFI (no Rust, no C bindings library),
running a child shell under a PTY and driving its byte stream through a 6-state
VT parser → cell grid → ANSI/CoreText renderer. Reference point: macOS
Terminal.app minimalism.

## Structure

```
void/
├─ src/              — entry + core byte→pixel loop (void_main.hexa), parsers, smokes
├─ core/sys/         — Layer 1: PTY, signals, termios, guardian (extern FFI)
├─ core/terminal/    — Layer 3: VT parser, cell grid, protocol, mouse, compat
├─ core/render/      — Layer 2: ANSI renderer (cell grid → host terminal)
├─ platform/         — Cocoa/Metal/CoreText extern bindings + ObjC bridges
├─ ui/               — Layer 4: tabs, layout, theme
├─ app/              — Layer 4: application entry variants
├─ plugin/           — Layer 5: plugin loader/API + hooks
├─ ai/               — Layer 6: inference, command palette, NEXUS-6 dashboard
├─ scripts/          — build/release glue (scratch/ = transient output)
├─ tests/            — per-feature + integrated 6-layer smokes, headless tests
├─ docs/             — design notes (each carries an SSOT quickref pointer)
├─ ARCHITECTURE.md   — final architecture SSOT (update-in-place)
├─ CHANGELOG.md      — history log (append-only)
└─ harness.config.json — harness governance configuration
```

## Governance

- **L0 CORE** files carry a `⛔ CORE — L0 불변식` banner and require user
  approval before edits — registered in `harness.config.json` `lockdown.files`:
  `core/sys/pty.hexa`, `core/terminal/vt_parser.hexa`,
  `core/terminal/grid.hexa`, `core/render/ansi.hexa`.
- **Single-doc discipline**: architecture goes in `ARCHITECTURE.md`
  (update-in-place SSOT), history in `CHANGELOG.md` (append-only), transient
  output under `scripts/scratch/`. Scattered root docs need a quickref back to
  the SSOT.
- **Changelog gate**: a `.hexa` code change requires a matching `CHANGELOG.md`
  entry in the same change.
- **Protected branches**: `main`, `master` — no direct commits; work on a branch
  and open a PR.
- **State** lives in `state.json` / `convergence.json` / `*.jsonl`, not in
  README/CHANGELOG.

## Harness

This repo is governed by the harness engine vendored as the `.harness-engine`
git submodule (`dancinlab/harness@harness-hardcore`). Hooks in
`.claude/settings.json` invoke it on bash / write / edit / prompt, each guarded
so the repo stays usable if the engine is absent
(`[ -x .harness-engine/bin/harness ] && <cmd> || true`).

Run the engine directly:

```bash
HARNESS_REPO_ROOT="$PWD" tsx "$PWD/.harness-engine/cli/index.ts" <cmd>
# fallback (npx): bash "$PWD/.harness-engine/bin/harness" <cmd>
```

## Quick reference

| Action | Command |
|--------|---------|
| Run void | `hexa run app/main.hexa` |
| Run a smoke | `hexa run src/smoke_pty.hexa` |
| Docs discipline check | `harness docs check` → expect `docs: ok` |
| Harness lint | `harness lint` |
| Post-edit check | `harness post edit <file>` |
