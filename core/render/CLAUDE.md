# render/ — L2 Render (L0 🔴)

ANSI 이스케이프 시퀀스 생성. 터미널 출력의 유일한 경로.

ansi.hexa   SGR포맷,커서이동,색상(2/16/256/TrueColor) — 320 LOC

색상 6티어: VT100(2) → xterm(16) → 256 → TrueColor(RGB) → Kitty → VOID-protocol
TrueColor 인코딩: 256 + R*65536 + G*256 + B (ossified, 변경 금지)

의존: sys/ (write). 참조: terminal/, ui/, app/
