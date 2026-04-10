# app/ — 엔트리포인트

main.hexa       PTY 열기 → 이벤트 루프 (read→parse→grid→render)
main_app.hexa   macOS Cocoa/Metal 윈도우 래퍼
main_tabs.hexa  멀티탭 초기화 하네스

의존: core/(전체), ui/, platform/
