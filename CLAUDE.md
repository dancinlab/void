<!-- L0 CORE — 수정 금지 -->
# void — HEXA 터미널 (FATHOM)

R14: shared/ JSON 단일진실, 이 파일은 트리 인덱스.

## 트리맵

```
core/           L1~L3 심장부 (L0 🔴) — sys/ render/ terminal/
ui/             L4 탭/레이아웃/테마 (L1 🟡)
plugin/         L5 플러그인 시스템 (L1 🟡)
ai/             L6 NEXUS-6 연동 (L2 🟢)
platform/       OS 브릿지 — macOS Cocoa/Metal (L1 🟡)
app/            엔트리포인트 — main, main_app, main_tabs
tests/          smoke + 통합 테스트
scripts/        빌드/릴리즈
docs/           설계문서/플랜
```

## 의존 방향

core/sys → core/render → core/terminal → ui → plugin → ai (단방향)

## ref

  lock      shared/config/core-lockdown.json
  rules     shared/config/absolute_rules.json    R1~R21 + VD1~VD2
  registry  shared/config/projects.json
  cfg       shared/config/project_config.json
  core      shared/config/core.json
  conv      shared/convergence/void.json
  api       shared/CLAUDE.md
