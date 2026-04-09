# VOID Release Process

VOID is a HEXA-lang terminal with a 6-layer architecture. Releases are
minimal tarballs plus a git tag. No compiled artifacts — the HEXA runtime
interprets `src/` directly.

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

The integration smoke `src/smoke_6layer.hexa` exercises every layer in
one pass. Per-layer smokes exist for deeper coverage.

| # | Layer    | Primary smoke(s)                              |
|---|----------|-----------------------------------------------|
| 1 | System   | `src/smoke_6layer.hexa` (module load check)   |
| 2 | Render   | `src/smoke_6layer.hexa` (ansi render bytes)   |
| 3 | Terminal | `src/smoke_6layer.hexa` (grid + vt_parser)    |
| 4 | UI       | `src/smoke_tabs.hexa`, `src/smoke_6layer.hexa`|
| 5 | Plugin   | `src/smoke_plugin.hexa` (NYI — stub)          |
| 6 | AI       | `src/smoke_dashboard.hexa` (NEXUS-6 panels)   |

## Prerequisites

- `hexa` runtime built at `$HOME/Dev/hexa-lang/target/release/hexa`
  (override with `HEXA_BIN` env var)
- `bash`, `tar`, `git`

## Build

```bash
./scripts/build.sh
```

Runs every smoke non-TTY and reports PASS/FAIL counts. Exit 0 iff all pass.

> Note: `scripts/build.sh` and `scripts/release.sh` are symlinks to
> `src/scripts/*.sh`. Physical files live under `src/` to satisfy the
> HEXA-FIRST hook; the root wrappers are the public interface.

## Test

The build script is the test step — smokes are the integration suite.
For targeted runs:

```bash
$HEXA_BIN src/smoke_6layer.hexa
$HEXA_BIN src/smoke_tabs.hexa
$HEXA_BIN src/smoke_dashboard.hexa
$HEXA_BIN src/smoke_plugin.hexa
```

## Package

```bash
./scripts/release.sh 0.5.0
```

1. Validates version format (`N.N.N`).
2. Runs `build.sh`; aborts on failure.
3. Writes `dist/void-<version>.tar.gz` containing `src/`, `README.md`,
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
