# void 인수인계 프롬프트 (2026-04-11)

아래를 새 세션 첫 메시지로 붙여넣기:

---

## void 터미널 — 실행 가능 바이너리 만들기

### 현재 상태
- **19 골화, 15/15 smoke pass, blocker 1건 (VB1 native build_c)**
- L1 (PTY/termios/poll/AppKit) ✅, L2 (VT/screen/UTF-8/SGR/CSI/OSC) ✅, L3 (entry/event loop/drawRect/title) ✅
- 모든 컴포넌트가 개별 smoke로 검증됨. **합치기만 하면 실행 가능.**

### 목표: `void_main.hexa` 1파일 생성 → 빌드 → 실행 가능한 터미널

합쳐야 할 smoke 코드:
1. `smoke_term_v1.hexa` — VT state machine + screen buffer (scr_init/scr_feed_byte/scr_put/scr_newline/scr_cup/scr_csi_*)
2. `smoke_csi_osc.hexa` — CSI 확장 (ED/EL/CUU/CUD/CUF/CUB/SGR no-op) + OSC 0 title 파싱
3. `smoke_app_entry.hexa` — AppKit + PTY + VT + screen 통합 파이프라인
4. `smoke_interactive.hexa` — NSEvent keyDown → PTY master 포워딩

빠진 조각 (새로 만들어야):
- **drawRect이 screen buffer를 Core Text로 렌더** (현재 "HEXA TERM v1" 하드코딩 → cell 배열의 codepoint를 글자로 그리기)
- **persistent event loop** (현재 timeout → 무한 루프 + Cmd+Q/window close 처리)
- **실시간 파이프라인**: key press → write to PTY → poll PTY → drain → VT feed → screen update → setNeedsDisplay → drawRect
- **OSC 0 → setTitle** 연결 (VT 파서에서 title 추출 → hexa_appkit_set_title_str)

### C/ObjC 수정 필요 (sys_appkit.m):
- `hexa_appkit_set_title_str(char* s)` — 동적 title 설정 (현재 하드코딩)
- drawRect에서 global screen buffer 읽기 (hexa→C 공유 메모리 or callback)
- `hexa_appkit_request_redraw()` — setNeedsDisplay 트리거

### 빌드 명령:
```bash
# 프로젝트 루트에서:
hexa $HOME/Dev/hexa-lang/self/build_c.hexa \
  src/void_main.hexa src/sys_pty.c src/sys_appkit.m \
  -framework Cocoa
```

### hexa-lang 주의:
- `[a, b, c]` statement 위치 금지 → `return [a, b, c]` 또는 `let x = [a, b, c]`
- `extern fn` 반환 타입은 `-> int` (long은 int로 매핑)
- string param은 annotation 필수: `fn foo(s: string)`
- 모듈 import 없음 → 전부 한 파일에 inline

### 참조 파일:
- `state.json` — SSoT (layers/blockers/next_steps)
- `shared/convergence/void.json` — 19건 골화
- `breakthroughs.jsonl` — 15 돌파
- `src/sys_pty.c` — C helpers (36 함수)
- `src/sys_appkit.m` — ObjC helpers (HexaDrawView/NSWindow/event)
- `CLAUDE.md` — 프로젝트 규칙

---
