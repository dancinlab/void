# void — Architecture (SSOT · update-in-place)

> Single source of truth for the final architecture. **Update (overwrite) this
> file in place** when the design changes — it is not append-only. History and
> decisions live in [CHANGELOG.md](CHANGELOG.md). Governance lives in
> [CLAUDE.md](CLAUDE.md).

## Overview

void is a terminal emulator written end-to-end in **hexa-lang**. It calls OS
APIs directly through hexa's `extern fn` FFI — no Rust, no C bindings library —
with only thin system helpers (PTY syscalls and Cocoa/AppKit glue) compiling
through C/ObjC. A child shell runs under a PTY; its byte stream is decoded
(UTF-8 + wide-char + Hangul NFC), driven through a 6-state VT parser, applied to
a cell grid, and rendered back out as ANSI to the host terminal (and, on macOS,
to a native AppKit/CoreText window). The reference design point is macOS
Terminal.app minimalism; every other emulator is explicitly excluded
(`rules.json` VD1).

The codebase is organized as a 6-layer stack (n=6):

```
Layer 6 — AI / Consciousness   intent, suggestion, NEXUS-6 dashboard   (ai/)
Layer 5 — Plugins              hexa scripting, hooks, themes           (plugin/, ui/theme)
Layer 4 — UI / Layout          tabs, layout, palette, status bar       (ui/, app/)
Layer 3 — Terminal Core        VT parser, cell grid, protocol, mouse   (core/terminal/)
Layer 2 — Rendering            ANSI emit, glyph/draw path              (core/render/, platform/)
Layer 1 — System               PTY, signals, termios, window/events    (core/sys/, platform/)
```

A single integrated, non-TTY smoke (`tests/smoke_6layer.hexa`) exercises every
layer in one run.

## Component map

| Component | Path | Layer | Role |
|-----------|------|-------|------|
| Entry / core loop | `src/void_main.hexa` | 1–4 | One byte → one pixel: PTY drain → UTF-8/wide/NFC → VT → CSI/SGR → grid → sync; main loop + tab/UI glue |
| Build/release glue | `scripts/build.hexa`, `scripts/release.hexa` | — | Two-stage compile via hexa-lang `build_c.hexa`; release packaging |
| PTY | `core/sys/pty.hexa` | 1 | openpty/fork/exec child shell, non-blocking read/write via libc extern (**L0 CORE**) |
| Signals / termios | `core/sys/signal.hexa`, `core/sys/term.hexa` | 1 | Signal handling, raw-mode terminal setup |
| Guardian | `core/sys/guardian.hexa` | 1 | System-level safety/watchdog helpers |
| VT parser | `core/terminal/vt_parser.hexa` | 3 | 6-state escape parser (ground/escape/CSI/OSC/DCS/VOID), DEC graphics (**L0 CORE**) |
| Cell grid | `core/terminal/grid.hexa` | 3 | Cell grid + scrollback, dirty-row tracking, SGR flags (**L0 CORE**) |
| Protocol | `core/terminal/protocol.hexa` | 3 | VOID-tier protocol handler |
| Mouse / compat | `core/terminal/mouse.hexa`, `core/terminal/compat.hexa` | 3 | Mouse reporting, xterm compatibility |
| Stream intel | `core/terminal/stream_intel.hexa` | 3 | Output-stream analysis |
| ANSI renderer | `core/render/ansi.hexa` | 2 | Renders cell grid back to host terminal via ANSI escapes (**L0 CORE**) |
| Platform bridges | `platform/macos.hexa`, `platform/common.hexa`, `platform/void_bridge*.m` | 1–2 | Cocoa/AppKit + Metal + CoreText extern bindings and ObjC glue |
| CLI parsing | `src/cmd_parser.hexa`, `src/prompt_parser.hexa`, `src/builtin_cmds.hexa` | 4 | Command/prompt parsing, built-in commands |
| History | `src/history_ring.hexa` | 4 | ↑/↓ history ring buffer |
| State SSOT | `src/state_ssot.hexa`, `state.json` | — | Runtime state pointers (progress lives here, not in README) |
| Tabs / layout | `ui/tab_*.hexa`, `ui/layout.hexa` | 4 | Tab model/bar/input/mux/session, panel layout |
| Theme | `ui/theme.hexa` | 5 | Color theme engine |
| Plugins | `plugin/plugin.hexa`, `plugin/example_plugin.hexa` | 5 | Plugin loader/API + hook system |
| AI | `ai/infer.hexa`, `ai/command_palette.hexa`, `ai/dashboard.hexa` | 6 | Inference, command palette, NEXUS-6 dashboard |
| App entry | `app/main.hexa`, `app/main_app.hexa`, `app/main_tabs.hexa` | 4 | Application entry variants |
| Smokes / tests | `src/smoke_*.hexa`, `tests/*.hexa`, `tests/headless/` | — | Per-feature smokes + integrated 6-layer smoke + headless tests |

## Data flow

```
                 ┌──────────────┐
   child shell ──┤  PTY (L1)    │  core/sys/pty.hexa — openpty/fork/exec, nonblock read
                 └──────┬───────┘
                        │  raw bytes
                        ▼
                 ┌──────────────┐
                 │ Decode (L3)  │  UTF-8 → wide-char width → Hangul NFC
                 └──────┬───────┘
                        ▼
                 ┌──────────────┐
                 │ VT parser    │  core/terminal/vt_parser.hexa — 6 states
                 │   (L3)       │  ground→escape→CSI/OSC/DCS/VOID dispatch
                 └──────┬───────┘
                        │  cell ops, SGR, cursor, scroll
                        ▼
                 ┌──────────────┐
                 │ Cell grid    │  core/terminal/grid.hexa — cells + scrollback,
                 │   (L3)       │  dirty-row marking
                 └──────┬───────┘
                        │  dirty cells
                        ▼
                 ┌──────────────┐        ┌────────────────────────┐
                 │ Render (L2)  │───────▶│ host terminal (ANSI)   │  core/render/ansi.hexa
                 │              │───────▶│ macOS window (CoreText)│  platform/macos.hexa + *.m
                 └──────────────┘        └────────────────────────┘

   keystrokes ──▶ UI/tabs (L4) ──▶ forward_keys ──▶ PTY write (L1) ──▶ child shell
                  ui/tab_*.hexa     prompt_parser.hexa
```

Input keystrokes flow the opposite direction: the UI/tab layer (`ui/`, `app/`)
forwards keys through `prompt_parser.hexa` into the PTY master fd, reaching the
child shell. Plugins (L5) hook events; the AI layer (L6) observes intent and
drives suggestions and the NEXUS-6 dashboard.

## Governance & verify

- **L0 CORE** files carry an inline `⛔ CORE — L0 불변식` invariant banner and
  require user approval before edits. They are registered in
  `harness.config.json` `lockdown.files`:
  `core/sys/pty.hexa`, `core/terminal/vt_parser.hexa`,
  `core/terminal/grid.hexa`, `core/render/ansi.hexa`.
- **Single-doc discipline** (harness `docs` module): this `ARCHITECTURE.md` is
  the update-in-place SSOT; `CHANGELOG.md` is the append-only log; transient
  output goes under `scripts/scratch/`. Scattered root reports must carry a
  quickref pointer back here.
- **Changelog gate**: code changes to `.hexa` sources require a matching
  `CHANGELOG.md` entry in the same change (harness `lint.changelog`).
- **Protected branches**: `main`, `master` — no direct commits (harness
  `lint.protectedBranches`).
- **Verify**: `harness docs check` must report `docs: ok`; the harness lint must
  report zero `CLAUDE-MD-*` violations.
- **State**: runtime progress lives in `state.json` / `convergence.json` /
  `breakthroughs.jsonl` / `pitfalls.jsonl`, not in README/CHANGELOG (`hexa.toml`
  `[state]`).
