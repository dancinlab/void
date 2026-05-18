<p align="center">
  <img src="docs/logo.svg" width="140" alt="void">
</p>

<h1 align="center">⬡ void</h1>

<p align="center"><strong>Void</strong> — grid-first terminal · Ghostty hard fork · N×M tiling as a core surface · structured agent I/O · perf-budget governance</p>

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <a href="https://github.com/ghostty-org/ghostty"><img alt="Based on Ghostty" src="https://img.shields.io/badge/based_on-ghostty-blueviolet"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%20·%20Linux-lightgrey">
  <img alt="Renderer" src="https://img.shields.io/badge/renderer-Metal%20·%20OpenGL-success">
  <img alt="Core" src="https://img.shields.io/badge/core-zig%20·%20swift-informational">
  <a href="https://github.com/dancinlab/void/tree/void/main"><img alt="Branch" src="https://img.shields.io/badge/branch-void%2Fmain-success"></a>
</p>

<p align="center">grid-mode · tiling-surface · terminal · pty · tool-call-stream · perf-first · zig · swift · gtk · metal · opengl</p>

---

Void is a hard fork of [Ghostty](https://github.com/ghostty-org/ghostty) where an N×M pane grid is a first-class rendering surface — not a window-manager bolt-on, not a tmux-style multiplexer process. When cell count `N` changes the layout auto-rebalances (`cols = ⌈√N⌉, rows = ⌈N/cols⌉, cols ≥ rows`), each cell carries its own cwd/env, and input can broadcast to all cells. It inherits Ghostty's engine (SIMD parser, Metal/OpenGL, per-terminal threads) and adds two more directions on top: a structured agent I/O channel alongside PTY, and a per-PR perf budget. Zig shared core, native Swift on macOS, GTK on Linux.

> [!NOTE]
> Part of the dancinlab n = 6 family — hexagonal icon, sibling to [NEXUS](https://github.com/dancinlab/nexus), [Anima](https://github.com/dancinlab/anima), [N6](https://github.com/dancinlab/canon), and [HEXA-LANG](https://github.com/dancinlab/hexa-lang). Void is a UX divergence from Ghostty, not a drop-in replacement; upstream syncs are selective cherry-picks only and full Ghostty history/credit is preserved.

## At a glance

```
   spawn a pane with cmd+ctrl+1..9 — the grid auto-rebalances

   N = 2          N = 4               N = 6                  N = 9
   ┌────┬────┐    ┌────┬────┐         ┌───┬───┬───┐          ┌───┬───┬───┐
   │ 1  │ 2  │    │ 1  │ 2  │         │ 1 │ 2 │ 3 │          │ 1 │ 2 │ 3 │
   │~/p │~/w │    ├────┼────┤         ├───┼───┼───┤          ├───┼───┼───┤
   └────┴────┘    │ 3  │ 4  │         │ 4 │ 5 │ 6 │          │ 4 │ 5 │ 6 │
                  │~/l │~/r │         │~/r│~/s│~/t│          ├───┼───┼───┤
   2 × 1          └────┴────┘         └───┴───┴───┘          │ 7 │ 8 │ 9 │
                  2 × 2               3 × 2                  └───┴───┴───┘
                                                             3 × 3

   cols = ⌈√N⌉   rows = ⌈N/cols⌉   cols ≥ rows   ·   per-cell cwd   ·   no manual resize handles   ·   no tmux
```

> Demo GIF (spawn → auto-rebalance → per-cell cwd): _pending — see release assets._

```sh
void                   # launch terminal
cmd+g                  # toggle grid mode <-> tab mode
cmd+ctrl+1..9          # spawn a tab in grid slot 1..9 (auto-rebalances)
cmd+ctrl+shift+1..9    # cycle tabs within a grid slot
cmd+ctrl+0             # broadcast input to all cells
```

## Why void

Three things upstream Ghostty treats as explicit non-goals — Void forks to take exactly these bets.

### 1. Grid mode — a first-class tiling surface

```
   cells = N                              on add / remove the whole grid
   ──────────────────────────────         re-balances to equal splits:
   N = 2  →  2 × 1                        cols = ⌈√N⌉
   N = 4  →  2 × 2                        rows = ⌈N/cols⌉
   N = 6  →  3 × 2                        cols ≥ rows (wider before taller)
   N = 9  →  3 × 3                        (no manual resize handles)
```

The N×M grid is a new renderer path, not a patch on the single-surface renderer and not a multiplexer process. Per-cell cwd / env, shared input routing, broadcast. No tmux, no prefix key, no config DSL to learn. This is the headline — the other two directions sit on top of it.

### 2. Ghostty hard fork — performance inherited, not rebuilt

Void did not rebuild a terminal. It hard-forks a fast one and changes three things. The SIMD parser, Metal (macOS) / OpenGL (Linux) renderers, and per-terminal render/read/write threads come straight from Ghostty. 4698 files were renamed Ghostty → Void at commit `964c9e32e`; upstream history and contributor credit are preserved (cherry-pick only, no clean merges).

### 3. AI-native I/O and a perf budget (secondary)

```
   shell process     ┌──── PTY ────────▶  traditional byte stream
        │            │
        ▼            ├──── AGENT ──────▶  structured tool-call events
   libvoid layer ────┤                    token stream w/ boundaries
        ▲            └──── META ───────▶  cwd, exit-code, span marks
        │
   agent process      (no wrapper process required)
```

A structured agent channel **alongside** PTY — tool-call events and token-stream boundaries as a data model, not heuristic-parsed from stdout. This is a downstream direction (P3), deliberately not the headline: Void is grid-first, not an "AI overlay" terminal. And every PR reports a delta against the Ghostty baseline — a **≥ 2 % regression blocks merge**, so a fork that adds features to a speed-chosen codebase cannot die by a thousand small regressions.

## Highlights

| | |
|---|---|
| ▦ | **Grid mode** — N×M pane grid as a core surface, auto-layout (`cols = ⌈√N⌉, rows = ⌈N/cols⌉`), per-cell cwd, broadcast |
| ⬡ | **Ghostty-grade performance** — SIMD parser, per-terminal render/read/write threads, Metal on macOS, OpenGL on Linux |
| ⚡ | **Perf budget** — every PR reports Δ against the Ghostty baseline; ≥ 2 % regression blocks merge |
| ◆ | **AI-native I/O** (P3) — agent protocol alongside PTY; structured tool-call / token-stream channels, no wrapper |
| ◈ | **Native UI** — SwiftUI on macOS (AppIntents, Shortcuts), GTK on Linux (systemd, cgroup isolation) |
| ⬢ | **dancinlab branding** — hexagonal icon, n = 6 family (NEXUS · Anima · N6 · HEXA · Void) |

## Architecture

```
       ┌──────────────────────────────────────────┐
       │            macOS App (Swift)             │
       │    SwiftUI · AppIntents · CoreText       │
       │        Metal renderer · native menu      │
       └──────────────┬───────────────────────────┘
                      │
       ┌──────────────▼───────────────────────────┐
       │          libvoid (Zig) — core            │
       │   parser · terminal state · renderer     │
       │   grid engine · agent I/O channel        │
       └──────────────┬───────────────────────────┘
                      │
       ┌──────────────▼───────────────────────────┐
       │            Linux App (GTK)               │
       │      systemd · OpenGL · FreeType         │
       └──────────────────────────────────────────┘
```

Zig-based shared core with platform-native shells. Core is C-ABI-compatible so it can be embedded in third-party projects (Ghostty's `libghostty` pattern — renamed to `libvoid` in this fork).

## Install

```sh
# 1. Install hexa-lang (gives you `hexa` + `hx` package manager)
curl -fsSL https://raw.githubusercontent.com/dancinlab/hexa-lang/main/install.sh | bash

# 2. Install void
hx install void
```

Or build from source — see [HACKING.md](HACKING.md). Default branch on the fork is `void/main`, not `main`.

## Run

```sh
void                   # launch terminal
void +show-config      # print active config
void +list-keybinds    # list keybindings
void +crash-report     # list crash reports
```

## Keybindings (default)

| Keys | Action |
|------|--------|
| `cmd+g` | toggle **grid mode ↔ tab mode** |
| `cmd+ctrl+1..9` | spawn new tab in grid slot **1..9** (stacks — repeated presses add tabs to the same slot) |
| `cmd+ctrl+shift+1..9` | cycle tabs within grid slot |
| `cmd+ctrl+0` | **broadcast** input to all cells |
| `cmd+opt+return` | find next (relocated from `cmd+g`) |
| `cmd+shift+opt+return` | find previous (relocated from `cmd+shift+g`) |
| `cmd+t` / `cmd+n` | new tab / new window |
| `cmd+d` / `cmd+shift+d` | split pane right / down |
| `cmd+,` | open settings |

All keys are rebindable via config — nothing is hardcoded.

## Fork status

| | |
|---|---|
| **Upstream** | [`ghostty-org/ghostty`](https://github.com/ghostty-org/ghostty) — cherry-picks only, no merges |
| **Fork date** | 2026-04-21 (from upstream commit `c3c8572f7`) |
| **Default branch** | `void/main` |
| **L3 rename** | complete — 4698 files renamed Ghostty → Void at commit `964c9e32e` |
| **CI** | `.github/workflows/build-fork.yml` on GitHub-hosted `macos-15` runners (ad-hoc codesign) |
| **Icon** | hexagonal, dancinlab n = 6 family |

See [VOID_FORK.md](VOID_FORK.md) for the full fork rationale, non-goals, and upstream policy.

## Roadmap

Checkpoints (done):

|  #  | Milestone                                  | Date       |
| :-: | ------------------------------------------ | :--------: |
| C0  | project-init — hexa scaffold               | 2026-04-21 |
| C1  | fork-base — Ghostty → Void rebrand         | 2026-04-21 |

Phases:

|  #  | Phase                                                               |  ETA       | Status |
| :-: | ------------------------------------------------------------------- | :--------: | :----: |
| P1  | **Grid mode + new-tab keybinding** — auto-grid, slot-spawn, mode toggle | 2026-05-18 |   ✅   |
| P2  | Stack analysis — map void renderer/apprt/terminal/font internals    | 2026-05-05 |   ⬜   |
| P3  | AI-native I/O protocol — structured agent channel alongside PTY     | —          |   ⬜   |
| P4  | Perf baseline — capture benches, set void regression budgets        | —          |   ⬜   |
| P5  | Diverge / upstream strategy — decide what feeds back vs stays void  | —          |   ⬜   |

P1 (grid mode) is complete: surface rendering, N×M auto-layout (`cols = ⌈√N⌉`), `cmd+ctrl+1..9` slot-spawn, broadcast, and per-cell cwd all landed. P4 (perf baseline) is next — capturing the Ghostty-baseline benches before further divergence accumulates.

## Non-goals

- **Not a drop-in Ghostty replacement** — Void will diverge in UX.
- **Not a shell** — Void drives shells, it does not replace them.
- **Not an "AI terminal"** — grid mode is the headline; agent I/O is a downstream direction, not an overlay.

## Crash reports

Void inherits Ghostty's crash reporter. Reports are saved to `$XDG_STATE_HOME/void/crash` (default `~/.local/state/void/crash`) and are **not** sent off your machine. Use `void +crash-report` to list. Reports use the [Sentry envelope format](https://develop.sentry.dev/sdk/envelopes/) with extension `.voidcrash`.

> [!WARNING]
> Crash reports contain full stack memory per thread at the time of the crash and can include sensitive data.

## Status

- P1 (grid mode + new-tab keybinding) **complete** (2026-05-18) — surface rendering, N×M auto-layout, slot-spawn, broadcast, per-cell cwd
- Fork date: 2026-04-21 (from upstream commit `c3c8572f7`); default branch `void/main` (not `main`)
- L3 rename complete — 4698 files renamed Ghostty → Void at commit `964c9e32e`
- Next: P4 perf baseline (capture Ghostty-baseline benches), then Show HN / r/commandline launch
- CI: `.github/workflows/build-fork.yml` on GitHub-hosted `macos-15` runners (ad-hoc codesign)

## Repo layout

```
void/
├── README.md
├── AGENTS.md / AGENTS.tape         project ops manual + machine-readable companion
├── VOID_FORK.md                    fork rationale + non-goals + upstream policy
├── HACKING.md / CONTRIBUTING.md    dev + contribution guides
├── LICENSE                         MIT
├── build.zig / build.zig.zon       Zig build entry + manifest
├── src/                            libvoid (Zig core) — parser · terminal state · renderer · grid · agent I/O
├── macos/                          Swift app (SwiftUI · AppIntents · Metal · CoreText)
├── linux/ + gtk/                   GTK app (systemd · OpenGL · FreeType)
├── pkg/                            vendored package wrappers
├── include/                        C-ABI headers for libvoid embedders
├── images/                         icon + brand assets (hexagon n=6 family)
├── docs/                           reference docs + logo.svg
├── conformance/                    terminal protocol conformance tests
├── bench/                          perf budget harness (Δ vs Ghostty baseline)
├── nix/ + flake.nix                Nix build entry
└── .github/workflows/              CI (build-fork.yml on macos-15 runners)
```

## Contributing

- **Contributing to Void** — [CONTRIBUTING.md](CONTRIBUTING.md)
- **Developing Void** — [HACKING.md](HACKING.md)
- **Fork rationale & upstream policy** — [VOID_FORK.md](VOID_FORK.md)

## Credits

Void is a hard fork of **[Ghostty](https://github.com/ghostty-org/ghostty)** by [Mitchell Hashimoto](https://mitchellh.com) and the Ghostty team. All Ghostty contributors are credited in upstream history, which is preserved in this repo. Divergent features (grid mode, AI-native I/O, perf harness) are Void-only.

## License

[MIT](LICENSE) — same license as upstream Ghostty. All Ghostty contributors are credited in upstream history (preserved in this repo); divergent features (grid mode, AI-native I/O, perf harness) are Void-only.

## Links

**[Atlas](https://dancinlab.github.io/TECS-L/atlas/)** · **[Papers](https://dancinlab.github.io/papers/)** · **[Ghostty docs](https://ghostty.org/docs)** · **[Contributing](CONTRIBUTING.md)** · **[Developing](HACKING.md)** · **[Fork rationale](VOID_FORK.md)**

<!-- SHARED:PROJECTS:START -->
<!-- AUTO:COMMON_LINKS:START -->
**[🎥 YouTube](https://www.youtube.com/@dancinlife)** · **[💬 Discord](https://discord.gg/mYzqYr67R)** · **[📬 Email](mailto:nerve011235@gmail.com)** · **[☕ Ko-fi](https://ko-fi.com/dancinlife)** · **[💖 Sponsor](https://github.com/sponsors/dancinlab)** · **[💳 PayPal](https://www.paypal.com/donate?business=nerve011235%40gmail.com)** · **[🗺️ Atlas](https://dancinlab.github.io/TECS-L/atlas/)** · **[📄 Papers](https://dancinlab.github.io/papers/)**
<!-- AUTO:COMMON_LINKS:END -->

## Main projects

> **[🧠 Anima](https://github.com/dancinlab/anima)** — Consciousness implementation. PureField repulsion-field engine + 1030 laws + Φ ratchet.
>
> **[🔭 NEXUS](https://github.com/dancinlab/nexus)** — Universal Discovery Engine. 216 lenses + OUROBOROS evolution + 5-phase singularity cycle.
>
> **[🏗️ N6 Architecture](https://github.com/dancinlab/canon)** — Architecture from perfect number 6. 225 AI techniques + chip design + crypto/OS/display.
>
> **[💎 HEXA-LANG](https://github.com/dancinlab/hexa-lang)** — The Perfect Number Programming Language. Working compiler + REPL.
>
> **[📄 Papers](https://github.com/dancinlab/papers)** — Complete paper collection (92 papers, Zenodo DOIs).

> **[Other projects →](https://github.com/orgs/dancinlab/repositories)**

## Community

[![Join our Discord](https://invidget.switchblade.xyz/mYzqYr67R)](https://discord.gg/mYzqYr67R)

Live research discussion, paper drops, stage-gate reviews, cross-project dispatch.

<!-- private repos는 projects.json의 private_repos 필드에 저장됨 (노출 금지) -->
<!-- SHARED:PROJECTS:END -->

---

<sub>⬡ Terminal as substrate. Grid as primitive. · Based on [Ghostty](https://github.com/ghostty-org/ghostty) · [dancinlab](https://github.com/dancinlab)</sub>
