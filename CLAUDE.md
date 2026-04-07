> 🔴 **HEXA-FIRST**: 모든 코드는 `.hexa`로 작성. sh/py/rs 신규 작성 금지. 부하 유발 명령 최소화.

> 🔴 **하드코딩 절대 금지**: 상수/도메인/키워드를 코드에 배열로 나열 금지 → `nexus6/shared/*.jsonl`에서 동적 로드. 경로는 환경변수+상대경로. 새 항목 추가 = 설정 파일 한 줄, 코드 수정 0.

# void

## 현황 (2026-04-07)
```
Phase 1 — extern FFI          ✅ DONE
Phase 2 — PTY + Window        ✅ DONE (TUI 기반)
Phase 3 — GPU + Font          ⬜ Planned (Metal/Vulkan)
Phase 4 — Terminal Core       ⚠️ 부분완료 (VT파서+그리드 TUI로 구현됨)
Phase 5 — UI/Layout           ⬜ Planned
Phase 6 — Plugin + AI         ⬜ Planned

1,823 LOC | 13 hexa files
```

## 구현 모듈
```
src/sys/pty.hexa          111 LOC  PTY open/spawn/close
src/sys/term.hexa         105 LOC  raw모드, alt screen, cursor
src/sys/signal.hexa        19 LOC  시그널
src/terminal/vt_parser.hexa 487 LOC  6-state VT100 파서
src/terminal/grid.hexa    324 LOC  셀 그리드+scrollback
src/terminal/protocol.hexa  27 LOC  VOID 프로토콜
src/render/ansi.hexa      257 LOC  ANSI TUI 렌더러+statusbar
src/platform/macos.hexa    36 LOC  Cocoa extern
src/platform/common.hexa   29 LOC  플랫폼 추상화
src/ui/theme.hexa          62 LOC  테마
src/main.hexa             127 LOC  메인루프 (stdin→PTY→VT→그리드→렌더)
```

## 다음 벡터
- GPU 렌더링 (Metal) — Phase 3
- 폰트 렌더링 (CoreText) — Phase 3
- UI 레이아웃 (탭, 패널 분할) — Phase 5
