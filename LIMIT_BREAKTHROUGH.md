<!-- @created: 2026-05-12 -->
<!-- @sister: LATTICE_POLICY.md §1.2 -->
---
project: void
domain: AI-native terminal — hard fork of Ghostty with grid mode (N×M tiling), AI-agent I/O at PTY layer, perf-budget-tracked-per-PR; Zig core + Swift macOS + GTK Linux
limits_audited: 8
breakthrough_candidates: 4
hard_walls: 2
soft_walls: 4
unclear: 2
---

# LIMIT_BREAKTHROUGH.md — void

## §1 Domain identification

Void is a terminal emulator forked from Ghostty with three non-negotiable
directions: (1) grid mode as a first-class tiling surface, (2) AI-agent I/O
baked into the terminal layer alongside PTY, (3) a perf budget tracked on
every PR, with ≥2% regression blocking merge. Stack: Zig shared core, Metal
renderer on macOS with SwiftUI app shell, OpenGL renderer with GTK on Linux,
SIMD parser.

As infrastructure, void is: a renderer + PTY + agent-protocol bridge. Its
real limits are squarely engineering / physics: frame-budget (display
refresh), input latency, parser throughput, GPU bandwidth, memory pressure
at large grid counts. Unlike anima or nexus, void is *not* a research artifact
— its limits are concrete and measurable on a wall-clock budget.

The three-directions axiom makes the limit picture clean: grid mode binds on
auto-layout complexity and cell-count scaling; AI-native I/O binds on
agent-protocol bandwidth and structured-stream parsing cost; perf-first binds
on Δ-vs-Ghostty per PR.

## §2 Real limits applicable to this project

| # | Limit | Class | Source / value | Applicability to void |
|---|-------|-------|----------------|------------------------|
| L1 | Display refresh / Nyquist | physics | 60 Hz → 16.67 ms frame budget; 120 Hz → 8.33 ms; ProMotion 120 Hz | Hard wall on render-latency budget. ≥1 dropped frame = visible jank. |
| L2 | Human input-perception threshold | physics / psychophysics | ~100 ms keystroke-to-glyph is "instant"; >250 ms feels laggy | Bounds tolerable end-to-end PTY-read → render path. |
| L3 | DRAM bandwidth (Roofline) | physics / engineering | ~100 GB/s LPDDR5; ~400 GB/s Apple M-series unified | Grid mode with N cells × W × H glyph framebuffers approaches memory-BW bound at large grids (e.g. 16×16 grid × 4K cells). |
| L4 | GPU fill-rate | engineering | Metal/M-series ~5 TFLOPs; OpenGL fill-rate varies | Per-frame glyph rasterization at large grid; binds atlas-update cost. |
| L5 | SIMD parser throughput | engineering | AVX2 / NEON ~10 GB/s for ANSI escape parsing | Caps PTY read rate per pane; Ghostty baseline is the reference. |
| L6 | PTY kernel I/O latency | engineering | macOS pty ~50 μs/round-trip; Linux ~30 μs | Floor for tool-call structured-stream RTT inside void. |
| L7 | Process / FD limits | engineering | macOS default ulimit -n = 256 (raise to 10K); Linux 1024 (raise to 1M) | N×M grid = N×M PTYs = N×M FDs. At 16×16 = 256 panes, default macOS limit binds. |
| L8 | Halting / undecidable agent loops | math | Rice's theorem | "AI-agent I/O" tools may issue unbounded outputs; void must enforce bounded patience without provably-terminating contract. |

(Skipped: any "n=6 grid layout" anchor per LATTICE_POLICY.md §1.3. Grid is `cols = ⌈√N⌉`, rows = `⌈N/cols⌉` — that is a layout heuristic, not a real limit.)

## §3 Per-limit breakthrough assessment

| Limit | Class | Current state | Breakthrough vector | Trigger metric |
|-------|-------|---------------|---------------------|----------------|
| L1 Display refresh | HARD_WALL | 16.67 ms / 8.33 ms / depends on monitor | None — display-bound; widening = require ProMotion 120 Hz or 240 Hz panels | n/a as breakthrough; document the floor |
| L2 Input perception 100 ms | HARD_WALL | Human factor; cannot be reduced | None — the lever is reducing void's contribution to the latency budget | End-to-end ≤ 30 ms at p99 |
| L3 DRAM Roofline | BREAKABLE_WITH_TECH | Grid mode at 4×4 / 16 panes well within BW; 16×16 = 256 panes pressures BW | Lazy glyph atlas + per-pane dirty-rect tracking; shared atlas across panes | Sustained 16×16 grid at 60 fps on M-series and on Linux LPDDR5 |
| L4 GPU fill-rate | BREAKABLE_WITH_TECH | Metal path optimized; OpenGL Linux path likely behind | Metal-equivalent batching on OpenGL; consider Vulkan path | Linux ≥ 80% Metal-baseline fill-rate at equivalent workload |
| L5 SIMD parser | SOFT_WALL | Ghostty SIMD baseline; void inherits | Per-architecture SIMD intrinsics audit (AVX512 / NEON v2); zero-copy from PTY buffer | Parser ≥ 12 GB/s; ≤ Ghostty parse-time + 0% |
| L6 PTY kernel I/O | SOFT_WALL | macOS pty ~50 μs RTT | io_uring on Linux; Mac kqueue tuning; structured agent channel can use pipes/sockets not PTY | Tool-call structured RTT ≤ 200 μs p99 |
| L7 FD limit | BREAKABLE_WITH_TECH | macOS default 256 binds at 16×16 grid; Linux 1024 binds at 32×32 | Document `ulimit -n` raise at startup; LaunchDaemon plist on macOS | 16×16 (= 256 panes) works on default macOS install without manual ulimit |
| L8 Agent-loop Rice-undecidability | HARD_WALL | Bounded-patience timeouts | None for general case; tool-call timeout + token-stream budget per turn | Documented timeout policy; runaway-agent test passes |

## §4 Top-3 breakthrough opportunities (this project)

1. **L7 — Default-friendly FD scaling.** Of all the limits, this is the one that binds *at exactly the grid sizes the README advertises* (16×16 = 256 panes, ≥macOS default). Auto-raise ulimit at startup or via LaunchDaemon plist removes the embarrassing failure mode. Trigger: 16×16 grid works on stock macOS without manual ulimit.
2. **L3 — Lazy glyph atlas + per-pane dirty rects.** As grid mode is the headline feature, the binding constraint at large N is DRAM bandwidth, not GPU. A shared atlas across panes with per-pane dirty-rect tracking cuts memory pressure proportionally. Trigger: sustained 60 fps at 16×16 on M-series.
3. **L6 — Structured agent channel ≠ PTY.** Routing tool-call / token-stream traffic through pipes or sockets (not PTY) drops the kernel-PTY-translation overhead, letting agent RTT approach pipe-IO floor (~10 μs) instead of pty floor (~50 μs). Trigger: ≤ 200 μs p99 for tool-call RTT.


- Display-refresh and human-perception limits (L1, L2) are *hard walls* — no engineering inside void breaks them. Void can only own its share of the budget; the rest is the panel and human nervous system.
- Rice's theorem (L8) makes "AI-agent always terminates inside budget" undecidable; bounded patience is the honest approximation.
- The 2%-Ghostty-regression CI gate is a policy, not a limit. The real underlying limit is whatever Ghostty itself does; voiding the gate just degrades to Ghostty performance.
- This audit does NOT verify any specific Zig file or perf-budget claim — only the architecture-level limit picture.
- Vulkan or Metal-3-feature-set arguments (L4) are out of scope for breakthrough framing; they are *engineering choices*, not limit-breaking.

## §6 References

- `LATTICE_POLICY.md` §1.2 (universal real-limits standard, 2026-05-12)
- `README.md` — Void three non-negotiable directions, perf-budget policy
- `VOID_FORK.md`, `AGENTS.md`, `HACKING.md`
- Ghostty upstream (https://github.com/ghostty-org/ghostty)
- Nyquist (1928), Roofline (Williams-Waterman-Patterson 2009), Rice (1953), POSIX pty / ulimit documentation
