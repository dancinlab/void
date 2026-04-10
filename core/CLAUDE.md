# core/ — L1~L3 심장부 (L0 🔴 Invariant)

VOID의 불변 핵심. PTY → ANSI 렌더 → VT 파서/그리드.

sys/        L1 PTY,시그널,libc extern — pty.hexa,term.hexa,signal.hexa
render/     L2 ANSI 시퀀스 생성 — ansi.hexa (320 LOC)
terminal/   L3 VT파서,셀그리드,마우스 — vt_parser.hexa(677),grid.hexa(512),mouse.hexa,protocol.hexa,compat.hexa

의존: sys → render → terminal (단방향, 역참조 금지)
수정 시 사용자 승인 필수. extern 시그니처 변경 → 모든 호출부 검증.
