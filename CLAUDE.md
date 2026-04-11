# void — HEXA 터미널 (FATHOM)

> shared/ JSON 단일진실 (R14). 규칙: `shared/rules/common.json` (R0~R27)

## ⛔ 규칙 준수 (필수)

작업 시작 전 `shared/rules/common.json` + `shared/rules/void.json` 을 읽고 전 규칙 준수. 위반 시 즉시 수정.

## 트리맵

```
core/           L1~L3 심장부 (L0) — sys/ render/ terminal/
ui/             L4 탭/레이아웃/테마
plugin/         L5 플러그인 시스템
ai/             L6 NEXUS-6 연동
platform/       OS 브릿지 — macOS Cocoa/Metal
app/            엔트리포인트 — main, main_app, main_tabs
tests/          smoke + 통합 테스트
scripts/        빌드/릴리즈
docs/           설계문서/플랜
```

## 의존 방향

`core/sys → core/render → core/terminal → ui → plugin → ai` (단방향)

## ref

```
rules     shared/rules/common.json             R0~R27 공통
project   shared/rules/void.json               VD1~VD2
lock      shared/rules/lockdown.json           L0/L1/L2
cdo       shared/rules/convergence_ops.json    CDO 수렴
registry  shared/config/projects.json
cfg       shared/config/project_config.json
core      shared/config/core.json
conv      shared/convergence/void.json
api       shared/CLAUDE.md
```
