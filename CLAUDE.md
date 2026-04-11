# void — hexa-only AI-native 터미널

> SSoT: `state.json`. 참조 기준: **macOS Terminal.app**. iTerm2/kitty/Warp/Ghostty/Alacritty 참조 제외 (VD1).

## state (모든 진행/결정은 JSON/JSONL에만)

| 파일 | 역할 |
|------|------|
| `state.json`         | 레이어·바이너리·블로커·next steps SSoT |
| `breakthroughs.jsonl` | 증명된 능력 append-only (15건) |
| `pitfalls.jsonl`     | 발견된 함정 append-only (8건, VP-01~VP-08) |
| `convergence.json`   | 골화 (ossified) 결정 — nexus `shared/convergence/void.json` 미러 |
| `rules.json`         | VD1~VD5 프로젝트 규칙 |
| `hooks.json`         | hook DSL — smoke-pass/fail/codegen-slow/iterm2-ref/discovery-emit |
| `manifest.json`      | 소스 파일 ↔ 레이어 ↔ 의존 |
| `hexa.toml`          | 패키지 매니페스트 (hexa-lang 기준) |

## layers (2026-04-11 현재)

| L | 역할 | 소스 | 골화 |
|---|------|------|------|
| L1_sys  | OS 브릿지 (PTY/termios/poll/Cocoa/AppKit FFI) | `src/sys_pty.c`, `src/sys_appkit.m` | 5건 ✅ |
| L2_term | VT 파서/스크린 버퍼/UTF-8/SGR/CSI/OSC (순수 hexa) | `src/smoke_*.hexa` | 6건 ✅ |
| L3_app  | 엔트리 + 이벤트 루프 + drawRect + OSC title | `src/smoke_app_entry.hexa`, `src/smoke_interactive.hexa` | 5건 ✅ |

### 골화 목록 (19건)

**결정 (3):** REFERENCE_TERMINAL_APP_ONLY, ARCHITECTURE_HEXA_ONLY, ARCHIVED_PRIOR_DESIGN
**L1 (5):** SYS_PTY_BINDING, SYS_TERMIOS_BINDING, SYS_POLL_SHELL_LOOP, SYS_BIDIR_FORWARDING, SYS_APPKIT_FFI
**L2 (5):** TERM_UTF8_GRAPHEME, TERM_VT_STATE_MACHINE, TERM_SCREEN_BUFFER, TERM_SGR_CELL_ATTR, TERM_CSI_EXPANSION, TERM_OSC_TITLE_PARSE
**통합 (1):** L2_L3_INTEGRATION_TERM_V1
**L3 (4):** APP_DRAWRECT, APP_OSC_TITLE, APP_ENTRY, APP_INTERACTIVE_EVENT_LOOP

## L0 Guard (공용)

`hexa ~/Dev/nexus/shared/lockdown/l0_guard.hexa <verify|sync|merge|status>` — REPO 자동 감지, SSOT `~/Dev/nexus/shared/lockdown/lockdown.json` projects.void.L0 배열로 파일 존재 / CODEOWNERS / GitHub branch protection 일괄 검증·복구. solo-repo PR 머지는 `merge <PR#>` (enforce_admins OFF→merge→ON 안전 패턴).

## src/ 구조

```
src/
  sys_pty.c              L1 C helper — forkpty/termios/poll/drain/write_byte
  sys_appkit.m           L1 ObjC helper — NSWindow/HexaDrawView/event pump/key input
  smoke_pty.hexa         L1 PTY spawn + read
  smoke_termios.hexa     L1 tcgetattr/tcsetattr 4 전이
  smoke_sh.hexa          L1 /bin/sh interactive + poll loop
  smoke_bidir.hexa       L1 stdin→PTY 양방향 포워딩
  smoke_appkit.hexa      L1 AppKit FFI (NSWindow open/close)
  smoke_utf8.hexa        L2 UTF-8 grapheme 파싱
  smoke_vt.hexa          L2 VT state machine (ESC/CSI/print)
  smoke_screen.hexa      L2 80x24 screen buffer
  smoke_sgr.hexa         L2 SGR cell attributes (fg/bg/bold)
  smoke_csi_osc.hexa     L2 CSI 확장 (ED/EL/CUU/CUD/CUF/CUB/SGR) + OSC 0 title 파싱 (12 tests)
  smoke_term_v1.hexa     L2+L3 통합 — PTY→VT→screen pipeline
  smoke_drawrect.hexa    L3 HexaDrawView + Core Text glyph
  smoke_osc_title.hexa   L3 OSC 0 window title
  smoke_app_entry.hexa   L3 통합 app_main — AppKit+PTY+VT+screen 전 파이프라인
  smoke_interactive.hexa L3 NSEvent keyDown → PTY master 이벤트 루프
```

## build / run

```bash
# 단건 빌드+실행 (smoke 단위)
cd ~/Dev/void
~/Dev/hexa-lang/hexa ~/Dev/hexa-lang/self/build_c.hexa \
  src/smoke_XXX.hexa src/sys_pty.c src/sys_appkit.m \
  -framework Cocoa

# 순수 hexa smoke (C helper 불필요)
~/Dev/hexa-lang/hexa ~/Dev/hexa-lang/self/build_c.hexa \
  src/smoke_csi_osc.hexa /tmp/void_csi_osc.c && \
  clang -O2 -w /tmp/void_csi_osc.c -o /tmp/void_csi_osc_bin && \
  /tmp/void_csi_osc_bin

# 전체 테스트 (state.json의 last_test)
./void --test
```

## 현재 블로커

```
VB1 native build_c   high   ./hexa self/build_c.hexa 45분 timeout (Rust 바이너리 self-compile 병목)
                             → hetzner/ubu 원격 빌드 or 사전 컴파일 build_c 캐시
```

> VB2 (use directive), VB3 (extern param 추론) 해소 완료 (2026-04-11).

## next (void_main.hexa — 실행 가능 터미널)

남은 1개 파일: **모든 smoke를 합친 `void_main.hexa`**
1. drawRect이 screen buffer cell을 Core Text로 렌더 (현재 하드코딩 "HEXA TERM v1")
2. persistent event loop (현재 1500ms/3s timeout → 무한 루프 + quit 핸들링)
3. key input → PTY → VT → screen → drawRect redraw 실시간 파이프라인
4. OSC 0 title passthrough (VT에서 파싱 → setTitle)

## 아카이브

이전 Metal/Vulkan 6-layer (core/ui/plugin/ai/platform) 설계 65 commits:
`~/archive/void_20260411_pre_terminalapp/`

## ref

```
rules        shared/rules/common.json       R0~R27
project      rules.json                     VD1~VD5
lockdown     shared/rules/lockdown.json     L0/L1/L2
convergence  shared/convergence/void.json   19건 골화
state        state.json                     SSoT
compiler     ~/Dev/hexa-lang/hexa
build_c      ~/Dev/hexa-lang/self/build_c.hexa
archived     ~/archive/void_20260411_pre_terminalapp/
```
