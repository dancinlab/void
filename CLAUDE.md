⚠️⚠️⚠️ 규칙 직접 작성 절대 금지 — shared/rules/ JSON만이 단일 진실 (R14)
⚠️ 이 파일은 nexus/shared/project-claude/void.md 마스터의 심링크. 원본만 수정.
⚠️ 공통 규칙: shared/rules/common.json (R0~R27) — 반드시 준수

# void — HEXA 터미널 (FATHOM)

R14: shared/ JSON 단일진실, 이 파일은 트리 인덱스.

## 돌파 시스템 (AI-native 자체 창발)

⚠️ "XXX 돌파" → blowup.hexa "XXX" 3 자동 실행 (문장 전달, 키워드 추출 ❌)
⚠️ 확인 질문 없이 즉시 Bash 실행할 것
```
hexa shared/blowup/core/blowup.hexa <문장> 3 --no-graph --seeds "$(hexa shared/blowup/seed/seed_engine.hexa merge | tr '|' ',')"
```

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

  rules     shared/rules/common.json             R0~R27 공통
  project   shared/rules/void.json               VD1~VD2
  lock      shared/rules/lockdown.json           L0/L1/L2
  cdo       shared/rules/convergence_ops.json    CDO 수렴
  registry  shared/config/projects.json
  cfg       shared/config/project_config.json
  core      shared/config/core.json
  conv      shared/convergence/void.json
  api       shared/CLAUDE.md
