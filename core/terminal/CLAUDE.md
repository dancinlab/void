# terminal/ — L3 Terminal Core (L0 🔴)

VT100/xterm 파서, 셀 그리드, 스크롤백. VOID의 심장.

vt_parser.hexa  L0 — 6-state VT 파서 (ground/escape/CSI/OSC/DCS/charset) 677 LOC
grid.hexa       L0 — Row×Col 셀 저장, 색상 속성, 스크롤백 버퍼 512 LOC
mouse.hexa      L1 — SGR/X10 마우스 프로토콜
protocol.hexa   L1 — VOID-protocol (L6 AI 연동)
compat.hexa     L2 — alt-screen, 커서 셰이프, 호환성

Phase 4 완료(ossified): TrueColor, 마우스, Alt screen, 리사이즈+리플로우
의존: sys/pty(read), render/ansi(write). 참조: ui/, app/
