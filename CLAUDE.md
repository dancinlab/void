# void

Grid-first terminal (Ghostty hard fork · N×M tiling as a core rendering surface · 🕳️). Beta: grid mode only. P1 grid-mode, dancinlab hexagon icon.

> 📍 **거버넌스 SSOT** — 이 문서는 `project.tape` 를 마크다운으로 재설계·단일화한 것이다 (`.tape` 은퇴).
> **설계 SSOT** = [`ARCHITECTURE.json`](ARCHITECTURE.json) (tree · update-in-place · human viewer `ARCHITECTURE.html` via `python3 serve.py`) · **이력** = [`CHANGELOG.md`](CHANGELOG.md). 이 문서 = 거버넌스 + 프로젝트 맵.
> parent: `dancinlab` · ssot: `github.com/dancinlab/void` (`hx install void`) · siblings: `hexa-lang`

## 거버넌스 (governance)

### grid auto-layout — N×M grid topology auto-rebalance
- ✅ grid auto-layout preserves `cols = ⌈√N⌉`, `rows = ⌈N/cols⌉`, `cols ≥ rows`; per-cell cwd isolation
- ⛔ break grid topology on cell-count change · add manual resize handles / splits (auto-only)

## 구조 (tree)

```
void/
├─ src/             — terminal core (zig): grid surface · pty · renderer · config · cli · font · input
├─ macos/           — macOS app shell (swift · AppKit/SwiftUI surface)
├─ include/         — public C headers (libvoid embed surface)
├─ vendor/          — vendored third-party sources
├─ pkg/             — packaged dependency wrappers
├─ test/            — test harness + fixtures
├─ tool/            — build/dev tooling scripts
├─ po/              — i18n translation catalogs
├─ docs/            — design & operations docs (logo.svg, guides)
├─ example/         — example configs / usage
├─ images/          — assets (icons, screenshots)
├─ dist/            — distribution build outputs
├─ snap/ · flatpak/ · nix/ · macos/ — packaging targets (snap · flatpak · nix · macOS)
├─ archive/         — superseded material
├─ state/           — runtime / persisted state (mmap session rings)
├─ void_self/       — void self-hosting / dogfooding surface
├─ install.hexa     — `hx install void` hook (builds from zig → /Applications/Void.app → bin shim)
├─ config.void      — shippable default config reference ($XDG_CONFIG_HOME/void/config.void)
├─ build.zig · build.zig.zon — zig build manifest + dependency lockset
├─ CMakeLists.txt · Makefile · Doxyfile — auxiliary build / docs-gen
├─ flake.nix · default.nix · shell.nix — nix dev/build environment
├─ ARCHITECTURE.json — 설계 tree SSOT (folded VOID.md/VOID.log.md 도메인 쌍, hexa-codex #161)
├─ ARCHITECTURE.html · serve.py — 사람용 트리 뷰어 (`python3 serve.py`, http)
├─ VOID_FORK.md · LATTICE_POLICY.md · LIMIT_BREAKTHROUGH.md · TAPE-AUDIT.md — fork/policy/audit docs
├─ AI_POLICY.md     — AI contribution policy
├─ HACKING.md · CONTRIBUTING.md · PACKAGING.md — contributor guides
├─ README.md        — project overview
├─ CHANGELOG.md     — change history (append-only)
└─ LICENSE · CODEOWNERS — MIT license + ownership
```
