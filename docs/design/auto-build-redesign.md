# PERF-P0-2 — auto-build 재설계 제안

**상태**: 설계안 (구현 전)
**작성일**: 2026-04-14
**브랜치**: `loop/perf-p0-2-auto-build-redesign`
**베이스 SHA**: 98353d0

---

## 1. 문제 정의

`b0f3eb9` (`chore(hooks): auto-build/auto-ship/void-swap 폐기`) 에서 `.claude/hooks/auto-build` + `.claude/hooks/auto-ship` + `.claude/hooks/void-swap` 3종이 전면 삭제되고 `.claude/settings.json` 의 `hooks` 블록이 `{}` 로 비워졌다. 커밋 메시지는 "자동 앱빌드 훅 전면 제거. settings.json hooks={} 로 이미 비활성" 한 줄이 전부이며, 폐기 사유는 본문에 명시되어 있지 않다 (가설: 다중 워크트리 × 병렬 에이전트 환경에서 PostToolUse hook 이 동시에 `hexa build` 를 트리거하여 빌드 경합/zombie 프로세스/로그 스팸이 발생했을 가능성 — 단정 불가, 확인 필요).

결과로 `src/*.hexa` / `src/*.c` / `src/*.m` 편집 후 매번 수동으로 `$HEXA_LANG/hexa build src/void_main.hexa` (또는 `hexa run self/build_c.hexa … -framework Cocoa`) 를 실행해야 하며, 이 빌드 자체가 VB1 (`native build_c 45분 timeout`) 블로커와 맞닿아 있어 수동 실행 비용이 크다. PERF-P0-2 는 이 자동화를 부활시키되 폐기 시 겪었던 문제를 재발하지 않는 구조로 재설계한다.

---

## 2. 옵션 3종 비교

| 항목 | A. fswatch daemon | B. Claude Code Hook 재구현 | C. Makefile + entr/watchexec |
|------|------------------|---------------------------|-----------------------------|
| 트리거 매체 | OS 파일시스템 이벤트 (`FSEvents`) | PostToolUse Edit/Write (JSON stdin) | 외부 CLI watcher (inotify-like) |
| 동작 범위 | 모든 편집 (Claude / 사람 / CI) | Claude 편집만 | 외부 watcher 구동 중 편집 |
| 동시성 제어 | daemon 내부 단일 큐 + debounce | 워크트리별 hook 병렬 실행 (제어 X) | watcher 1개 = 사용자 몫 |
| 의존성 | `fswatch` (이미 설치 확인) | Claude Code + hexa-hook-filter.sh | `entr` / `watchexec` (둘 다 미설치) |
| 워크트리 × 21 호환 | daemon 1개가 전체 커버 가능 | 워크트리당 settings.json 1개 — 경합 위험 | 워크트리당 사용자가 수동 기동 |
| 디버깅 | launchctl list / 파일 로그 | hook stderr 캡처 제한적 | 전경 프로세스 → 즉시 가시 |
| 폐기 사유 재발 위험 | 낮음 (프로세스 1개) | 높음 (hooks 전면 폐기 직접 원인 가능성) | 매우 낮음 (수동 기동) |

### A. fswatch + 백그라운드 daemon

`launchd` user agent 혹은 `nohup fswatch` 로 `$VOID/src/` 를 감시한다. `fswatch -l 0.5` (latency 500ms) 으로 디바운스하고, 이벤트 수신 시 내부 mutex 보호 하에 `hexa build` 를 1회 실행한다. 빌드 중 추가 이벤트는 "dirty" 플래그로 병합해 빌드 종료 후 재실행한다.

- **장점**: Claude / 사람 / 스크립트 편집 모두 커버, hook 메커니즘 전면 폐기 결정과 독립, 워크트리 21개 환경에서도 daemon 1개로 일관됨 (혹은 워크트리별 source path 만 subscribe).
- **단점**: launchd plist 관리 + 로그 로테이션 필요, macOS 전용 (`fswatch` 는 포터블하지만 agent 기동 방식이 OS 종속), daemon 리크 시 좀비 빌드 프로세스 발생 가능.

### B. Claude Code Hook 재구현 (PostToolUse Edit/Write 필터)

`.claude/settings.json` 에 PostToolUse hook 을 다시 등록하고 `matcher: "Edit|Write"` 로 제한, 스크립트에서 `file_path` 를 파싱해 `src/*.{hexa,c,m}` 만 통과시킨다 (삭제된 `.claude/hooks/auto-build` 스크립트의 `case` 문 그대로 재활용 가능).

- **장점**: Claude 작업 컨텍스트와 이벤트가 정확히 일치, 편집→빌드 latency 가 가장 짧음, `systemMessage` JSON 으로 Claude UI 에 실패 메시지 직접 노출 가능.
- **단점**: 일반 셸 편집 (vim/nano/외부 툴) 시 미동작, 21개 워크트리가 같은 `settings.json` 을 공유하므로 여러 에이전트가 동시에 같은 파일을 편집하면 hook 이 병렬 기동되어 clang 경합 발생. **특히** 폐기 커밋 `b0f3eb9` 의 커밋 메시지가 "전면 제거" 인 점 — 본문에 구체 원인 기록 없음 — 을 고려하면 같은 사유 (아마도 병렬 빌드 경합 또는 빌드 시간 초과로 turn 지연) 재발 가능성 존재 (가설).

> 인용 (`git show b0f3eb9`): "자동 앱빌드 훅 전면 제거. settings.json hooks={} 로 이미 비활성."

### C. Makefile + entr/watchexec 외부 도구

`Makefile` 에 `build` / `watch` 타겟을 만들고 `make watch` 가 `entr` (또는 `watchexec`) 로 `src/` 를 감시→`make build` 재실행. 개발자가 별도 터미널 탭/tmux 페인에서 `make watch` 를 띄워놓는 형태.

- **장점**: 도구가 모두 표준 CLI — 디버깅·로그·kill 단순, hook 메커니즘 완전 독립, Makefile 자체가 문서 역할, 병렬 에이전트는 각자 자기 워크트리에서 `make build` 수동 호출 가능 (자동화 없음 = 경합 없음).
- **단점**: `entr` / `watchexec` 현재 로컬 미설치 (`which` 결과 확인), 사용자가 "터미널 탭 하나 띄워놓기" 를 잊으면 자동 빌드 미동작 → 사실상 수동 빌드와 동일, 21개 워크트리마다 별도 watcher 기동 부담.

---

## 3. 추천 — **옵션 A (fswatch daemon) + Makefile `build` 타겟 병행**

본 프로젝트 특성상 **옵션 A 를 추천**한다. 근거:

1. **빌드 시간**: §5 실측에서 `hexa build` 가 `hexa_v2` 네이티브 컴파일러 경로로 진입 (VB1 블로커 — `native build_c 45분 timeout`) → 빌드 1회가 분 단위. hook 기반 (옵션 B) 이면 빌드 중 turn 이 지연되거나 여러 워크트리 hook 이 동시 기동될 때 경합이 폐기 사유를 재현할 가능성 높음.
2. **워크트리 수 21개 × 동시 에이전트**: PostToolUse hook 은 워크트리마다 독립 실행되므로 8+ 병렬 편집 시 8+ 개의 `hexa_v2` 프로세스가 동시 기동 — 메모리/CPU 포화. Daemon 단일 큐 + debounce 는 구조적으로 이를 회피.
3. **Makefile 병행**: 옵션 C 의 Makefile 부분만 채택 (`make build` / `make watch`) — daemon 이 죽어도 수동 회복 경로 확보, 옵션 A 의 스크립트는 결국 `make build` 를 호출하면 됨.

---

## 4. 1단계 PoC 스코프 (체크리스트)

**구현은 다음 PR 에서 진행**. 본 문서는 스코프만 확정.

- [ ] **Step 1** — 루트에 `Makefile` 신규 작성. 타겟: `build` (= `hexa build src/void_main.hexa -o /Applications/VOID.app/Contents/MacOS/void_term`), `install` (codesign + atomic mv), `test` (`VOID_TEST=1`), `clean`.
- [ ] **Step 2** — `.claude/scripts/void-autobuild.sh` 신규 — `fswatch -l 0.5 src/ | while read; do flock /tmp/void-autobuild.lock make build; done` 1 파일, 20줄 이내. `flock` 으로 동시 빌드 차단.
- [ ] **Step 3** — `launchctl` user agent plist `~/Library/LaunchAgents/dev.void.autobuild.plist` 초안 작성 (KeepAlive=true, RunAtLoad=false, 로그 `~/.void/autobuild.log`). 기본은 **수동 load** — `launchctl load …` 를 사용자가 명시적으로 호출.
- [ ] **Step 4** — `docs/design/auto-build-redesign.md` (본 문서) 에 "PoC 실행 결과" 섹션 추가 (빌드 latency p50/p95, 로그 샘플, daemon RSS).
- [ ] **Step 5** — rollback 절차 문서화: `launchctl unload` 1줄 + `make` 타겟만 남기기.

### 검증 방법

1. **빌드 성공**: `touch src/void_main.hexa` → 500ms 이내 daemon 이벤트 수신 → `make build` 완료 → `VOID_TEST=1 void_term` 스모크 PASS.
2. **Latency 측정**: 편집 시각 ↔ `void_term` 재시작 시각 델타. 목표 p50 < 전체 빌드 시간 + 1s (파일 이벤트 오버헤드).
3. **경합 테스트**: 3개 워크트리에서 동시에 `src/*.hexa` 편집 → daemon 이 3 이벤트를 큐에 직렬화, 빌드 3회 (병렬 0회) 확인.
4. **복구 테스트**: `kill -9 $(pgrep fswatch)` → launchd KeepAlive 가 30s 이내 재기동 확인.

### 롤백 계획

1. `launchctl unload ~/Library/LaunchAgents/dev.void.autobuild.plist && rm -f $_` (daemon 제거).
2. `.claude/scripts/void-autobuild.sh` 삭제.
3. `Makefile` 은 유지 (수동 `make build` 워크플로 지속).
4. 본 문서에 "PoC 실패 근거 3줄" 추가.

### 비-목표 (명시)

- **hook 재도입 금지**: 옵션 B 는 채택하지 않음. `.claude/settings.json` 의 `hooks: {}` 상태 유지.
- **auto-ship/void-swap 부활 금지**: 본 PR 범위는 "빌드" 자동화만. 커밋/푸시/배포는 별 이슈.
- **병렬 빌드 시도 금지**: daemon 은 단일 빌드만 직렬 실행. 빌드 간 병렬화는 `hexa-lang` 쪽 VB1 해소가 선행 조건.

---

## 5. 관측 — 빌드 시간 실측

**환경**: macOS 24.6.0 (Darwin), Apple Silicon, `hexa` stage1 CLI (2026-04-13~), 단일 빌드 실행 (병렬 X).

**소스 크기**:

| 파일 | LOC |
|------|-----|
| `src/void_main.hexa` | 2345 |
| `src/sys_pty.c` | 611 |
| `src/sys_appkit.m` | 5770 |
| **합계** | **8726** |

**단계별 시간**:

| 단계 | 커맨드 | wall | 비고 |
|------|--------|------|------|
| 전처리 (hexa→C) | `hexa run self/build_c.hexa src/void_main.hexa …` | **6.82s** (user 6.52s, sys 0.23s, 99% CPU) | **실패** — `index 124249 out of bounds (len 124249)` 런타임 에러. 86450→124249 bytes preprocessed 후 단계에서 panic. 기존 auto-build hook 의 `/tmp/void_main.c` 산출 경로도 동일한 증상 재현 중 (build_c.hexa 버전 회귀 추정 — 별도 이슈로 등록 필요). |
| 전체 빌드 (`hexa build`) | `hexa build src/void_main.hexa -o /tmp/void_term_test` | **>2분 05초 미완료 (측정 abort)** | `hexa_v2` 네이티브 경로로 진입해 VB1 (`native build_c 45분 timeout`) 과 동일 증상 재현. t=22s: hexa_v2 ~455MB RSS 활성, t=125s: `hexa build` 메인 99.6% CPU 여전히 루프 중, `/tmp/void_term_test` 미생성. SIGTERM 으로 abort. 사용자 context ("이미 4분+ 걸림") 및 VB1 와 정합. |
| 링크 (clang → native bin) | `clang -O2 -w -ObjC /tmp/void_main.c src/sys_pty.c src/sys_appkit.m -framework Cocoa -o void_term` | **측정 미완 — TODO** | 전처리 실패로 blocked. 과거 auto-build hook 본문 기준 clang 단일 단계는 수초 예상 (추정).

**관측 결론**:

- `hexa run build_c.hexa` 경로 = 6.8s 후 실패 (회귀 의심, 별도 디버그 필요 — 본 설계와 독립된 이슈).
- `hexa build` 경로 = VB1 블로커로 분 단위 (자주 45분 초과) — daemon debounce 500ms 가 빌드 중 재트리거 되는 빈도와 비교하면 daemon-level 큐 머지가 **반드시** 필요.
- 따라서 옵션 A 의 `flock` + debounce + dirty-flag 머지 구조가 정당화됨.
- `/tmp/void_main.c` 기반 mtime 캐시 (폐기된 `.claude/hooks/auto-build` 의 구현) 도 Makefile 에 포팅 필요 — `.hexa` 미변경 시 hexa→C 재실행 스킵으로 대다수 편집 (`.c`/`.m`) 의 빌드를 clang-only 로 단축 가능 (이 경로의 소요 시간은 **측정 미완 — TODO**, 추정 수초).

---

## 6. 참조

- 폐기 커밋: `b0f3eb9` (`chore(hooks): auto-build/auto-ship/void-swap 폐기`)
- 폐기된 구현: 아래 경로는 삭제됨 (git 히스토리에만 존재)
  - `.claude/hooks/auto-build` — PostToolUse Edit/Write hook, `src/*.{m,c,hexa}` 필터, atomic mv + codesign, 100줄
  - `.claude/hooks/auto-ship` — Stop hook, git commit/push + 재빌드, 56줄
  - `.claude/hooks/void-swap` — 전경 helper, mtime-cache 재구성, 85줄
- VB1 블로커: `CLAUDE.md:25` — `native build_c 45분 timeout (self-compile 병목)`
- 관련 문서: `docs/design/hexa-blockers.md`, `docs/docs/design.md`
