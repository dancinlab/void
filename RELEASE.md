# VOID Release Process

VOID is a HEXA-lang terminal with a 6-layer architecture. Releases are
minimal tarballs plus a git tag. No compiled artifacts — the HEXA runtime
interprets source directories directly.

## Version Numbering

| Phase | Version line | Scope                         |
|-------|--------------|-------------------------------|
| 1     | 0.1.x        | extern FFI                    |
| 2     | 0.2.x        | PTY + Window (TUI)            |
| 3     | 0.3.x        | GPU + Font                    |
| 4     | 0.4.x        | Terminal Core (VT + grid)     |
| 5     | 0.5.x        | UI / Layout (tabs, panels)    |
| 6     | 0.6.x        | Plugin + AI                   |

Current work targets **0.5.x** (Phase 5).

## 6 Layers and Smokes

The integration smoke `tests/smoke_6layer.hexa` exercises every layer in
one pass. Per-layer smokes exist for deeper coverage.

| # | Layer    | Primary smoke(s)                                  |
|---|----------|----------------------------------------------------|
| 1 | System   | `tests/smoke_6layer.hexa` (module load check)      |
| 2 | Render   | `tests/smoke_6layer.hexa` (ansi render bytes)      |
| 3 | Terminal | `tests/smoke_6layer.hexa` (grid + vt_parser)       |
| 4 | UI       | `tests/smoke_tabs.hexa`, `tests/smoke_6layer.hexa` |
| 5 | Plugin   | `tests/smoke_plugin.hexa` (NYI — stub)             |
| 6 | AI       | `tests/smoke_dashboard.hexa` (NEXUS-6 panels)      |

## Prerequisites

- `hexa` runtime built at `$HOME/Dev/hexa-lang/target/release/hexa`
  (override with `HEXA_BIN` env var)
- `bash`, `tar`, `git`

## Build

```bash
hexa scripts/build.hexa
```

Runs every smoke non-TTY and reports PASS/FAIL counts. Exit 0 iff all pass.

> Note: `scripts/build.hexa` and `scripts/release.hexa` live under
> `scripts/`.

## Test

The build script is the test step — smokes are the integration suite.
For targeted runs:

```bash
$HEXA_BIN tests/smoke_6layer.hexa
$HEXA_BIN tests/smoke_tabs.hexa
$HEXA_BIN tests/smoke_dashboard.hexa
$HEXA_BIN tests/smoke_plugin.hexa
```

## Package

```bash
hexa scripts/release.hexa 0.5.0
```

1. Validates version format (`N.N.N`).
2. Runs `build.hexa`; aborts on failure.
3. Writes `dist/void-<version>.tar.gz` containing `app/`, `core/`, `ui/`, `plugin/`, `ai/`, `platform/`, `README.md`,
   `LICENSE`, `CLAUDE.md`, `CHANGELOG.md`, `RELEASE.md`. Dotfiles and
   `dist/` itself are excluded.
4. Prints tag/push instructions (does **not** tag or push).

## Tag

```bash
git tag v0.5.0
git push --tags
```

Tag names follow `vMAJOR.MINOR.PATCH`.

## Publish

Attach `dist/void-<version>.tar.gz` to the GitHub release for the tag.
No registry publication — VOID is source-distributed.

---

## CHANGELOG Template

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Changed
- ...

### Fixed
- ...

### Removed
- ...
```

Follow [Keep a Changelog](https://keepachangelog.com/) conventions.
Move items from `[Unreleased]` into the new version block on release.
