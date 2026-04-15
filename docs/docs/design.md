# hexa-only AI-native 터미널 설계

> 2026-04-11. **Terminal.app 미니멀리즘 철학 채택. 구현은 전부 hexa-only.**

## 참조 기준

**macOS Terminal.app 하나만.** iTerm2/Warp/kitty/Alacritty 등은 참조에서 제외 —
기능 확장 경로는 혼선만 일으킴. "Terminal.app이면 충분하다"가 출발선.

## Terminal.app 설계 핵심 (우리가 따라할 부분)

1. **단일 프로세스 + AppKit 네이티브 렌더링** — 별도 GPU 파이프라인 없음
2. **NSTextView + Core Text** — 시스템이 이미 로드한 렌더 경로 재사용, 공짜
3. **VT100/xterm-256color subset만** — 파서 분기 최소
4. **기능 자체를 적게 유지** — 코드 경로 없음 = CPU 부하 없음
5. **단순 scrollback (NSAttributedString)** — 검색 인덱스/mark 불필요

핵심 원칙: **"부하가 없는" 게 아니라 "부하 낼 기능이 없어서" 가볍다.**

## 우리의 방향

### 설계 원칙

1. **기능 삭제가 최적화다**
   split/minimap/외부 도구 통합 전부 안 넣는다. 정말 필요한 것만.

2. **단일 프로세스 + 단순 파서**
   xterm-256color subset만. truecolor/OSC 8/OSC 133 세 개까지만 허용.
   Sixel/Kitty graphics 의도적 배제.

3. **hexa-only 구현**
   - 파서, 상태머신, 스크롤백 버퍼, 이벤트 루프 — 전부 `.hexa`
   - PTY/termios 시스템콜만 C helper 위임
   - 렌더링은 AppKit NSWindow + NSView + Core Text (Terminal.app과 동일 경로)

4. **AI-native는 기능이 아니라 구조다**
   - 출력 스트림에 singularity/gap detector 내장 (hook DSL)
   - 프로젝트 감지 (project-aware) 기본 탑재 — `CLAUDE.md`/`shared/rules` 자동 로드
   - 에이전트가 직접 입출력을 읽고 쓰는 PTY-level API 내장
   - discovery 허브(`shared/discovery/growth_bus.jsonl`)로 세션 이벤트 방출

5. **버릴 것 (의도적 미지원)**
   - 별도 GPU 렌더러 (Core Text로 충분)
   - 탭/스플릿 (별도 전용 도구 영역)
   - 패스워드 매니저, 북마크, 프로파일 상속
   - 플러그인 시스템 (hook DSL 하나로 충분)
   - instant replay / 세션 저장

## 벤치마크 목표 (vs Terminal.app)

| 항목 | 목표 |
|------|------|
| cold start | ≤ Terminal.app (~200ms) |
| idle CPU | 0% (프레임타이머 없음) |
| 100k lines scrollback 메모리 | ≤ 2x Terminal.app |
| paste 100k chars 처리 | ≤ 50ms |
| binary size | ≤ 5MB (hexa runtime 포함) |

## 필요 hexa-lang 선행 작업

1. ✅ PTY 바인딩 (`openpty`, `forkpty`) — C helper + .hexa wrapper
2. ✅ termios struct 바인딩 (save/raw/cbreak/restore)
3. ✅ poll + bidir forwarding
4. ✅ UTF-8 grapheme cluster iterator (pure hexa)
5. ✅ VT100 state machine (pure hexa)
6. ✅ 스크린 버퍼 + 커서 + CUP params (pure hexa)
7. ✅ 통합 증명 — sh → PTY → VT → screen buffer (term v1)
8. ⏳ AppKit FFI — NSApplication + NSWindow 최소 바인딩
9. ⬜ Core Text 글리프 렌더 (monospace grid)
10. ⬜ 인터랙티브 이벤트 루프 (키 입력 → PTY master)
11. ⬜ SGR 속성 → cell attr (fg/bg/bold/italic/underline)
12. ⬜ native build_c (iteration 해금)
