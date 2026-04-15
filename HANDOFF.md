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
hexa $HEXA_LANG/self/build_c.hexa \
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

## REPL-P0-4 reconnect smoke (ROI/VD6)

void_server 는 이미 daemon + ckpt 지속성 완비 (5초 주기 checkpoint + detach/disconnect/shell-exit/shutdown flush + 부팅 시 `scan_and_restore_checkpoints` + ATTACH 때 `reanimate_session`). 이 섹션은 reconnect 경로를 수동으로 검증하는 레시피.

### 사전 조건
- `/Applications/VOID.app/Contents/MacOS/void_term` 및 `void_server` 설치됨
- `/tmp/void_server.sock` 접근 가능, `/tmp/void_server_ckpt/` 쓰기 가능

### 단계 1 — 깨끗한 상태에서 기동
```bash
pkill -f void_server; pkill -f void_term; sleep 1
rm -f /tmp/void_server.sock
rm -rf /tmp/void_server_ckpt && mkdir -p /tmp/void_server_ckpt
VOID_SERVER_FOREGROUND=1 VOID_SERVER_VERBOSE=1 \
  /Applications/VOID.app/Contents/MacOS/void_server &
SERVER_PID=$!
sleep 1
ls -la /tmp/void_server.sock      # 소켓 생성 확인
```

### 단계 2 — void_term 기동 + 세션 생성
```bash
open -n /Applications/VOID.app           # 또는 void_term 직접 실행
# 창에서 "echo VOID_CKPT_MARKER_$(date +%s)" 입력 + 엔터
# 잠깐 대기 (>=5초: 주기 checkpoint 트리거)
sleep 6
ls -la /tmp/void_server_ckpt/*.bin       # 1개 이상의 .bin 파일 기대
```

### 단계 3 — void_term 강제 종료 (세션은 서버에 살아있어야)
```bash
pkill -9 -f void_term
sleep 1
ps aux | grep -v grep | grep -E "void_server|void_term"
# 기대: void_server 만 남음 (세션 shell 프로세스도 살아있음)
ls -la /tmp/void_server_ckpt/*.bin       # .bin 남아있음
```

### 단계 4 — void_term 재실행 → 세션 복구
```bash
open -n /Applications/VOID.app
# 세션 선택 UI (Cmd+L / 탭 list) 에서 이전 세션 ID 표시 확인
# 해당 세션에 attach → 이전 scrollback 프레임(마지막 체크포인트) 보여야 함
# 프롬프트가 살아있으면 reanimate_session 이 새 shell을 띄움 + 그리드 재활용
```

### 단계 5 — 서버 크래시 복구
```bash
kill -9 $SERVER_PID
sleep 1
VOID_SERVER_FOREGROUND=1 VOID_SERVER_VERBOSE=1 \
  /Applications/VOID.app/Contents/MacOS/void_server &
# stderr 에 "pruned N old checkpoint(s)" 또는 tombstone 로드 확인
# 새 void_term 띄우고 LIST → 복구된 세션 tombstone 표시
```

### PASS 기준
- 단계 3 후: void_term 죽어도 `/tmp/void_server_ckpt/*.bin` 잔존
- 단계 4 후: 재실행한 void_term 이 같은 session_id 로 attach 하면 이전 그리드 + (reanimate 된) live shell 모두 보임
- 단계 5 후: 서버 재기동 시 `scan_and_restore_checkpoints` 가 `.bin` 을 tombstone 세션으로 등록, LIST 에 나타남

### 참조 코드 위치 (src/void_server.c)
- `checkpoint_session` L758 / `scan_and_restore_checkpoints` L829 / `reanimate_session` L724
- 주기 체크포인트 L1640-L1651 (VS-07, 5s 간격)
- detach flush L1150, 연결 해제 flush L1321, shell EOF flush L1441, 종료 flush L1657
- 클라이언트 side `sys_appkit.m` L3199 SPAWN / L3427 ATTACH
