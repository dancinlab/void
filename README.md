# VOID

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
