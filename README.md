<p align="center">
  <img src="docs/logo.svg" width="140" alt="void">
</p>

<h1 align="center">⬡ void</h1>

<p align="center"><strong>Void</strong> — AI-native terminal · grid-mode first · structured agent I/O · perf-first · hard fork of Ghostty</p>

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <a href="https://github.com/ghostty-org/ghostty"><img alt="Based on Ghostty" src="https://img.shields.io/badge/based_on-ghostty-blueviolet"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%20·%20Linux-lightgrey">
  <img alt="Renderer" src="https://img.shields.io/badge/renderer-Metal%20·%20OpenGL-success">
  <img alt="Core" src="https://img.shields.io/badge/core-zig%20·%20swift-informational">
  <a href="https://github.com/dancinlab/void/tree/void/main"><img alt="Branch" src="https://img.shields.io/badge/branch-void%2Fmain-success"></a>
</p>

<p align="center">terminal · grid-mode · ai-native-io · pty · tool-call-stream · perf-first · zig · swift · gtk · metal · opengl</p>

---

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Based on Ghostty](https://img.shields.io/badge/based%20on-ghostty-blueviolet.svg)](https://github.com/ghostty-org/ghostty)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](#)
[![Renderer](https://img.shields.io/badge/renderer-Metal%20%7C%20OpenGL-brightgreen.svg)](#)
[![Zig + Swift](https://img.shields.io/badge/core-zig%20%2B%20swift-orange.svg)](#)
[![Branch](https://img.shields.io/badge/branch-void%2Fmain-success.svg)](https://github.com/dancinlab/void/tree/void/main)
[![Discord](https://img.shields.io/badge/discord-join-5865F2.svg?logo=discord&logoColor=white)](https://discord.gg/u2spd3wwU)

# ⬡ Void — AI-native Terminal

**Grid-mode first. AI-native I/O. Perf-first. Based on [Ghostty](https://github.com/ghostty-org/ghostty).**

```
    ┌──── Grid ────┐       ┌──── Agent ────┐       ┌──── Perf ────┐
    │  N × M panes │  ⇄   │  PTY + tool   │  ⇄   │  SIMD parser │
    │  auto-layout │       │  structured   │       │  Metal/OpenGL│
    │  per-cell cwd│       │  token stream │       │  Δ vs ghostty│
    └──────────────┘       └───────────────┘       └──────────────┘
               ▲                   ▲                      ▲
               └────── three non-negotiable directions ───┘
```

> Void is a hard fork of [Ghostty](https://github.com/ghostty-org/ghostty) rebuilt around three directions the upstream is not taking: grid mode as a first-class tiling surface (not a plugin), AI-agent I/O baked into the terminal layer alongside PTY, and a perf budget tracked on every PR. Zig shared core, native Swift on macOS, GTK on Linux.

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

## 💬 Community

[![Join our Discord](https://invidget.switchblade.xyz/mYzqYr67R)](https://discord.gg/mYzqYr67R)

Live research discussion, paper drops, stage-gate reviews, cross-project dispatch.

<!-- private repos는 projects.json의 private_repos 필드에 저장됨 (노출 금지) -->
<!-- SHARED:PROJECTS:END -->





---

## Highlights

| | |
|---|---|
| ⬡ | **Ghostty-grade performance** — SIMD parser, per-terminal render/read/write threads, Metal on macOS, OpenGL on Linux |
| ▦ | **Grid mode** — N×M pane grid as a core surface, auto-layout (cols = ⌈√N⌉, rows = ⌈N/cols⌉), per-cell cwd |
| 🤖 | **AI-native I/O** — agent protocol alongside PTY; structured tool-call / token-stream channels, no wrapper |
| ⚡ | **Perf budget** — every PR reports Δ against the Ghostty baseline; ≥ 2 % regression blocks merge |
| 🎨 | **Native UI** — SwiftUI on macOS (AppIntents, Shortcuts), GTK on Linux (systemd, cgroup isolation) |
| ⬢ | **dancinlab branding** — hexagonal icon, n = 6 family (NEXUS · Anima · N6 · HEXA · Void) |

## Three non-negotiable directions

Void is not a drop-in Ghostty replacement. It will diverge in UX, and upstream syncs are selective cherry-picks only.

### 1. Grid mode — first-class tiling surface

```
   cells = N                              cells auto-layout
   ──────────────────────────────         cols = ⌈√N⌉   rows = ⌈N/cols⌉
   N = 2  →  2 × 1                        cols ≥ rows (wider before taller)
   N = 4  →  2 × 2
   N = 6  →  3 × 2                        ┌──────┬──────┬──────┐
   N = 9  →  3 × 3                        │  1   │  2   │  3   │
                                          │ ~/p  │ ~/w  │ ~/l  │
   on add/remove: whole grid              ├──────┼──────┼──────┤
   re-balances to equal splits            │  4   │  5   │  6   │
   (no manual resize handles)             │ ~/r  │ ~/s  │ ~/t  │
                                          └──────┴──────┴──────┘
```

N×M pane grid as a core surface concept — **not** a window-manager bolt-on. Auto-grid: when cell count N changes, the layout re-balances to `cols × rows` with `cols = ⌈√N⌉, rows = ⌈N/cols⌉, cols ≥ rows`. Per-cell cwd / env. Shared renderer. New renderer path (not a patch on the single-surface renderer). MVP ships as N=2 horizontal split, then generalizes to N×M.

### 2. AI-native I/O

```
   shell process     ┌──── PTY ────────▶  traditional byte stream
        │            │
        ▼            ├──── AGENT ──────▶  structured tool-call events
   libvoid layer ────┤                    token stream w/ boundaries
        ▲            └──── META ───────▶  cwd, exit-code, span marks
        │
   agent process      (no wrapper process required)
```

Running an agent does not require a wrapper. The terminal layer itself speaks both PTY and a structured channel — tool calls, token stream boundaries, and result spans are first-class, not heuristic-parsed from stdout.

### 3. Perf-first

Speed, memory, GPU time, and syscall budgets are a tracked first-class concern. Every PR reports delta against the Ghostty baseline. Regressions ≥ 2 % block merge.

```
           Ghostty baseline              Void target
   parse:  SIMD AVX2/NEON         →      + tool-call fast path
   render: Metal / OpenGL         →      + grid batch reuse
   memory: arena + screen rings   →      + per-cell allocator
   sys:    read/write/render thr. →      + agent-channel thread
```

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

```bash
# 1. Install hexa-lang (gives you `hexa` + `hx` package manager)
curl -fsSL https://raw.githubusercontent.com/dancinlab/hexa-lang/main/install.sh | bash

# 2. Install void
hx install void
```

Or build from source — see [HACKING.md](HACKING.md). Default branch on the fork is `void/main`, not `main`.

## Run

```bash
void                   # launch terminal
void +show-config      # print active config
void +list-keybinds    # list keybindings
void +crash-report     # list crash reports
```

## Keybindings (default, Phase 1)

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
| P1  | **Grid mode + new-tab keybinding** — auto-grid, slot-spawn, mode toggle | 2026-04-28 |   🛠   |
| P2  | Stack analysis — map void renderer/apprt/terminal/font internals    | 2026-05-05 |   ⬜   |
| P3  | AI-native I/O protocol — structured agent channel alongside PTY     | —          |   ⬜   |
| P4  | Perf baseline — capture benches, set void regression budgets        | —          |   ⬜   |
| P5  | Diverge / upstream strategy — decide what feeds back vs stays void  | —          |   ⬜   |

Current state (P1): `toggle_grid_mode` action and `cmd+g` keybind wired at commit `326e5f15`. Surface rendering, auto-layout, and slot-spawn land in the rest of P1 — MVP is N=2 horizontal split, then generalizes to N×M.

## Non-goals

- **Not a drop-in Ghostty replacement** — Void will diverge in UX.
- **Not a shell** — Void drives shells, it does not replace them.

## Crash reports

Void inherits Ghostty's crash reporter. Reports are saved to `$XDG_STATE_HOME/void/crash` (default `~/.local/state/void/crash`) and are **not** sent off your machine. Use `void +crash-report` to list. Reports use the [Sentry envelope format](https://develop.sentry.dev/sdk/envelopes/) with extension `.voidcrash`.

> [!WARNING]
> Crash reports contain full stack memory per thread at the time of the crash and can include sensitive data.

## Contributing

- **Contributing to Void** — [CONTRIBUTING.md](CONTRIBUTING.md)
- **Developing Void** — [HACKING.md](HACKING.md)
- **Fork rationale & upstream policy** — [VOID_FORK.md](VOID_FORK.md)

## Credits

Void is a hard fork of **[Ghostty](https://github.com/ghostty-org/ghostty)** by [Mitchell Hashimoto](https://mitchellh.com) and the Ghostty team. All Ghostty contributors are credited in upstream history, which is preserved in this repo. Divergent features (grid mode, AI-native I/O, perf harness) are Void-only.

## Links

**[🗺️ Atlas](https://dancinlab.github.io/TECS-L/atlas/)** · **[📄 Papers](https://dancinlab.github.io/papers/)** · **[Ghostty docs](https://ghostty.org/docs)** · **[Contributing](CONTRIBUTING.md)** · **[Developing](HACKING.md)** · **[Fork rationale](VOID_FORK.md)**

## Status

- Fork date: 2026-04-21 (from upstream commit `c3c8572f7`)
- Default branch: `void/main` (not `main`)
- L3 rename complete — 4698 files renamed Ghostty → Void at commit `964c9e32e`
- Phase 1 (Grid mode + new-tab keybinding) in flight — `toggle_grid_mode` + `cmd+g` wired at commit `326e5f15`; surface rendering / auto-layout / slot-spawn pending
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

## License

[MIT](LICENSE) — same license as upstream Ghostty. All Ghostty contributors are credited in upstream history (preserved in this repo); divergent features (grid mode, AI-native I/O, perf harness) are Void-only.

---

<sub>⬡ Terminal as substrate. Grid as primitive. · Based on [Ghostty](https://github.com/ghostty-org/ghostty) · [dancinlab](https://github.com/dancinlab)</sub>
