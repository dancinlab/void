# VOID Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).
Versions track the 6-layer architecture phase (Phase N → 0.N.x).

## [Unreleased]

### Added
- Phase 5 좌측 탭 UI — `ui/` 6 modules (tab_model, tab_bar, tab_input,
  tab_mux, tab_session, layout) with S1–S7 step slices.
- n=6 컬러 테마 6종 — `ui/theme.hexa` shipping six curated palettes.
- NEXUS-6 대시보드 스텁 — `ai/dashboard.hexa` with 6 layer panels.
- 6-layer 통합 스모크 — `tests/smoke_6layer.hexa` exercising every layer
  in a single non-TTY run.
- Release pipeline — `scripts/build.sh`, `scripts/release.sh`,
  `RELEASE.md`, and this `CHANGELOG.md`.
