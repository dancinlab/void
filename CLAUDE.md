# void — hexa-only AI-native 터미널

commands: shared/config/commands.json — autonomous 블록으로 Claude Code가 작업 중 smash/free/todo/go/keep 자율 판단·실행
rules: shared/rules/common.json (R0~R27) + rules.json (VD1~VD5)
L0 Guard: `hexa ~/Dev/nexus/shared/lockdown/l0_guard.hexa <verify|sync|merge|status>`
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

build: ~/Dev/hexa-lang/hexa ~/Dev/hexa-lang/self/build_c.hexa src/smoke_XXX.hexa src/sys_pty.c src/sys_appkit.m -framework Cocoa
blocker: VB1 — native build_c 45분 timeout (self-compile 병목)

next (void_main.hexa): drawRect→screen buffer Core Text 렌더, persistent event loop, key→PTY→VT→screen→drawRect 파이프라인, OSC 0 title passthrough

ref:
  rules        shared/rules/common.json       R0~R27
  project      rules.json                     VD1~VD5
  lockdown     shared/rules/lockdown.json     L0/L1/L2
  convergence  shared/convergence/void.json   19건 골화
  state        state.json                     SSoT
  compiler     ~/Dev/hexa-lang/hexa
  build_c      ~/Dev/hexa-lang/self/build_c.hexa
  archived     ~/archive/void_20260411_pre_terminalapp/
