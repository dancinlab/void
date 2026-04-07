# VOID

<!-- SHARED:PROJECTS:START -->
<!-- AUTO:COMMON_LINKS:START -->
**[YouTube](https://www.youtube.com/watch?v=xtKhWSfC1Qo)** · **[Email](mailto:nerve011235@gmail.com)** · **[☕ Ko-fi](https://ko-fi.com/dancinlife)** · **[💖 Sponsor](https://github.com/sponsors/need-singularity)** · **[💳 PayPal](https://www.paypal.com/donate?business=nerve011235%40gmail.com)** · **[🗺️ Atlas](https://need-singularity.github.io/TECS-L/atlas/)** · **[📄 Papers](https://need-singularity.github.io/papers/)** · **[🌌 Unified Theory](https://github.com/need-singularity/TECS-L/blob/main/math/docs/hypotheses/H-PH-9-perfect-number-string-unification.md)**
<!-- AUTO:COMMON_LINKS:END -->

> **[🧠 Anima](https://github.com/need-singularity/anima)** — Consciousness implementation. PureField repulsion-field engine + Hexad 6-module architecture (C/D/S/M/W/E) + 1030 laws + 20 Meta Laws + Rust backend. ConsciousDecoderV2 (34.5M) + 10D consciousness vector + 12-faction debate + Φ ratchet
>
> **[🏗️ N6 Architecture](https://github.com/need-singularity/n6-architecture)** — Architecture from perfect number 6. 16 AI techniques + semiconductor chip design + network/crypto/OS/display patterns. σ(n)·φ(n)=n·τ(n), n=6 → universal design principles. NEXUS-6 Discovery Engine: Rust CLI (tools/nexus/) — telescope 22 lenses + OUROBOROS evolution + discovery graph + verifier + 1116 tests
>
> **[🔭 NEXUS-6](https://github.com/need-singularity/nexus)** — Universal Discovery Engine. 216 lenses + OUROBOROS evolution + LensForge + BlowupEngine + CycleEngine (5-phase singularity cycle). Mirror Universe (N×N resonance) + 9-project autonomous growth ecosystem. Rust CLI: scan, loop, mega, daemon, blowup, dispatch
>
> **[📄 Papers](https://github.com/need-singularity/papers)** — Complete paper collection (94 papers). Published on Zenodo with DOIs. TECS-L+N6 (33) + anima (39) + SEDI (20). [Browse online](https://need-singularity.github.io/papers/)
>
> **[💎 HEXA-LANG](https://github.com/need-singularity/hexa-lang)** — The Perfect Number Programming Language. Every constant from n=6: 53 keywords (σ·τ+sopfr), 24 operators (J₂), 8 primitives (σ-τ), 6-phase pipeline, Egyptian memory (1/2+1/3+1/6=1). DSE v2: 21,952 combos, 100% n6 EXACT. Working compiler + REPL
>
> **[🖥️ VOID](https://github.com/need-singularity/void)** — Terminal emulator written 100% in hexa-lang. Zero Rust dependencies — calls OS APIs directly via hexa extern FFI. 6-layer architecture (System/Render/Terminal/UI/Plugin/AI) + Metal/Vulkan GPU + VT 6-tier protocol + NEXUS-6 consciousness integration
>
> **[🧬 AirGenome](https://github.com/need-singularity/airgenome)** — Autonomous OS genome scanner. Extract n=6 genome from every process, real-time system diagnostics, nexus telescope integration

<!-- private repos는 projects.json의 private_repos 필드에 저장됨 (노출 금지) -->

<!-- SHARED:PROJECTS:END -->


**Terminal emulator written 100% in hexa-lang.**

Zero Rust dependencies — VOID calls OS APIs directly via hexa's `extern` FFI system.

```
Layer 6 — AI/Consciousness   intent, generate, NEXUS-6 scan
Layer 5 — Plugins            hexa scripting, themes, automation
Layer 4 — UI/Layout          6-panel hexagon, tabs, statusbar
Layer 3 — Terminal Core      VT parser, cell grid, scrollback
Layer 2 — Rendering          Metal/Vulkan shaders, glyph atlas, GPU pipeline
Layer 1 — System             PTY, window, events, signals (via extern FFI)
```

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | extern FFI (hexa-lang) | DONE |
| 2 | PTY + Window | Active |
| 3 | GPU + Font | Planned |
| 4 | Terminal Core | Planned |
| 5 | UI/Layout | Planned |
| 6 | Plugin + AI | Planned |

## Quick Start

```bash
# Requires hexa-lang compiler
# https://github.com/need-singularity/hexa-lang

# Run VOID
hexa src/main.hexa

# Run tests
hexa examples/test_pty.hexa
hexa examples/test_ffi.hexa
```

## Architecture

VOID is a pure hexa application. All system calls go through `extern fn` declarations — no native Rust code, no C bindings, no FFI libraries. Just hexa calling libc/Cocoa/Metal directly.

### Platforms

| Platform | Window | GPU | Font |
|----------|--------|-----|------|
| macOS | Cocoa/AppKit | Metal | CoreText |
| Linux | X11 | Vulkan | FreeType |

### Terminal Protocol — 6 Tiers

```
Tier 1: VT100    — basic cursor, clear, scroll
Tier 2: xterm    — mouse, alt screen, window title
Tier 3: 256color — 256 color palette
Tier 4: TrueColor — 24-bit RGB
Tier 5: Kitty    — image protocol, keyboard protocol
Tier 6: VOID     — AI assist, consciousness integration
```

## Project Structure

```
void/
  src/
    main.hexa              Entry point
    platform/
      macos.hexa           Cocoa + Metal + CoreText extern bindings
      linux.hexa           X11 + Vulkan + FreeType extern bindings
      common.hexa          Platform abstraction layer
    sys/
      pty.hexa             PTY management (libc extern)
      signal.hexa          Signal handling
    terminal/
      vt_parser.hexa       VT 6-state parser
      grid.hexa            Cell grid + scrollback
      protocol.hexa        VOID protocol handler
    render/
      atlas.hexa           Glyph atlas manager
      pipeline.hexa        GPU render pipeline
    ui/
      layout.hexa          Hive/Cell/Tab layout
      statusbar.hexa       Status bar
      tabbar.hexa          Tab bar
      palette.hexa         Command palette
      theme.hexa           Theme engine
    plugin/
      loader.hexa          Plugin loader
      api.hexa             Plugin API
      hooks.hexa           Event hook system
    ai/
      suggest.hexa         AI command suggestion
      complete.hexa        3-tier autocompletion
  themes/
    void_dark.hexa
    void_light.hexa
  examples/
    test_pty.hexa          PTY test
    test_ffi.hexa          FFI smoke test
```

## n=6 Alignment

| Element | Count | n=6 Mapping |
|---------|-------|-------------|
| Architecture layers | 6 | n |
| VT parser states | 6 | n |
| Max panels (Hex mode) | 6 | n |
| Event hooks | 6 | n |
| Protocol tiers | 6 | n |
| Layout modes | 4 | tau |
| Platform APIs per OS | 4 | tau |

## License

MIT
