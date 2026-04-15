# void — hexa-only AI-native 터미널

<!--
# @convergence-meta-start
# project: void
# purpose: void 골화 (ossified) 목록 — 더 이상 수정하지 않는 확정된 결정/구현
# updated: 2026-04-11
# @convergence-meta-end
#
# @convergence-start
# state: ossified
# id: VC-01
# value: Terminal.app 단일 참조 결정
# date: 2026-04-11
# rule: VD1
# locked: true
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-02
# value: hexa-only 로직 + sys_ 프리픽스 C/ObjC helper 구조
# date: 2026-04-11
# rule: VD2
# locked: true
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-03
# value: 이전 void 설계 (Metal/Vulkan/6-layer/plugin) 아카이브
# date: 2026-04-11
# locked: true
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-04
# value: HexaTermView drawRect → Core Text glyph grid 렌더
# date: 2026-04-11
# locked: true
# src: src/sys_appkit.m (HexaTermView)
# evidence: 동적 grid + SFMono 13pt + Terminal.app ANSI 팔레트. 11/11 self-test pass.
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-05
# value: 이벤트 루프 — AppKit poll + PTY poll_read + hexa_keys_to_pty(C-side)
# date: 2026-04-11
# locked: true
# src: src/void_main.hexa main loop
# evidence: 포인터 FFI 없음. T7 PTY→VT→screen 63바이트 검증.
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-06
# value: void_main.hexa 통합 바이너리 (L1+L2+L3)
# date: 2026-04-11
# locked: true
# src: src/void_main.hexa + sys_pty.c + sys_appkit.m
# evidence: hexa→C + clang arm64 ~100KB. 11/11 self-test.
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-07
# value: UTF-8 멀티바이트 디코딩 (2/3/4바이트 → codepoint)
# date: 2026-04-11
# locked: true
# src: src/void_main.hexa scr_feed_byte GROUND state
# evidence: T10 한글 U+D55C=54620 검증. 박스드로잉/한글/CJK 정상 표시.
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-08
# value: 동적 grid 크기 + forkpty winsize + 리사이즈 TIOCSWINSZ
# date: 2026-04-11
# locked: true
# src: sys_appkit.m (auto-size 85%) + sys_pty.c (hexa_pty_resize)
# evidence: T9 120x40 wrap 검증. T11 100x30 PTY 파이프라인. forkpty(&ws) 직접 전달.
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-09
# value: 좌측 탭바 + Cmd+T/W/Q + 탭 클릭 전환
# date: 2026-04-11
# locked: true
# src: sys_appkit.m (VoidTab, HexaTermView mouseDown/keyDown)
# evidence: 탭별 PTY + grid save/restore(memcpy). single-instance lock.
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-10
# value: VOID.app 번들 + /Applications 설치 + Dock 아이콘
# date: 2026-04-11
# locked: true
# src: VOID.app/Contents/{Info.plist, Resources/AppIcon.icns, MacOS/void_term}
# evidence: Spotlight/Dock 실행. Terminal.app 없이 독립 동작.
# @convergence-end
#
# @convergence-start
# state: ossified
# id: VC-11
# value: Terminal.app 매칭 — SFMono 13pt + 블랙 배경 + ANSI 팔레트
# date: 2026-04-11
# locked: true
# src: sys_appkit.m (term_color, drawRect, init_term)
# evidence: defaults read com.apple.Terminal → SFMono-Regular 13pt. 동일 폰트/색상 적용 확인.
# @convergence-end
-->

commands: shared/config/commands.json — autonomous 블록으로 Claude Code가 작업 중 smash/free/todo/go/keep 자율 판단·실행
rules: shared/rules/common.json (R0~R27) + rules.json (VD1~VD5)
L0 Guard: `hexa $NEXUS/shared/harness/l0_guard.hexa <verify|sync|merge|status>`
loop: 글로벌 `~/.claude/skills/loop` + 엔진 `$NEXUS/shared/harness/loop` — roadmap `$NEXUS/shared/roadmaps/void.json` 3-track×phase×gate 자동
SSoT: state.json. 참조 기준: macOS Terminal.app (iTerm2/kitty/Warp/Ghostty/Alacritty 제외 VD1)

state files:
  state.json         레이어·바이너리·블로커·next steps SSoT
  breakthroughs.jsonl 증명된 능력 append-only (15건)
  pitfalls.jsonl     함정 append-only (8건, VP-01~VP-08)
  convergence.json   골화 — shared/convergence/void.json 미러
  rules.json         VD1~VD5
  hooks.json         hook DSL
  manifest.json      소스↔레이어↔의존
  hexa.toml          패키지 매니페스트

layers (L1=OS브릿지 5골화, L2=VT파서 6골화, L3=앱+이벤트 5골화, 총 19골화):
  L1_sys:  sys_pty.c, sys_appkit.m — PTY/termios/poll/Cocoa/AppKit FFI
  L2_term: smoke_*.hexa — VT파서/스크린버퍼/UTF-8/SGR/CSI/OSC
  L3_app:  smoke_app_entry.hexa, smoke_interactive.hexa — 엔트리+이벤트루프+drawRect

build: $HEXA_LANG/hexa run $HEXA_LANG/self/build_c.hexa src/smoke_XXX.hexa src/sys_pty.c src/sys_appkit.m -framework Cocoa   (stage1 CLI, 2026-04-13~)
fast path: `SKIP_TRANSPILE=1 ./scripts/build_void.sh` — ObjC(.m)/C(.c) 편집만이면 hexa 트랜스파일 생략, clang 재링크만 (~5초). 기존 `$ARTIFACT` 필요.
blocker: VB1 — native build_c 45분 timeout (self-compile 병목)
terminfo install: `tic -x -o ~/.terminfo extras/terminfo/void-256color.terminfo` (PTY child TERM=void-256color)

next (void_main.hexa): drawRect→screen buffer Core Text 렌더, persistent event loop, key→PTY→VT→screen→drawRect 파이프라인, OSC 0 title passthrough

ref:
  rules        shared/rules/common.json       R0~R27
  project      rules.json                     VD1~VD5
  lockdown     shared/rules/lockdown.json     L0/L1/L2
  convergence  shared/convergence/void.json   19건 골화
  state        state.json                     SSoT
  compiler     $HEXA_LANG/hexa
  build_c      $HEXA_LANG/self/build_c.hexa
  archived     ~/archive/void_20260411_pre_terminalapp/
