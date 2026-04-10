# sys/ — L1 System (L0 🔴)

OS 직접 호출. libc extern FFI로 PTY/시그널/터미널 제어.

pty.hexa      openpty,fork,execvp,ioctl — PTY 생성/스폰/리사이즈
term.hexa     raw mode,커서,색상,시그널 제어 (tcgetattr/tcsetattr)
signal.hexa   SIGWINCH,SIGTERM 핸들러

블로커: pty_resize stub (hexa에 chr(int) 필요)
의존: libc only. 최하위 레이어.
