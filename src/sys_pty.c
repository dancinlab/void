// examples/pty_helpers.c — hexa-lang PTY helpers (first-light smoke).
// Exposes hexa_pty_* symbols that link into build_c.hexa-generated
// .c files via extern fn declarations. These symbols are additive —
// they do not collide with build_c.hexa's inline runtime (which
// does NOT define anything with the hexa_pty_ prefix).
//
// Scope: smoke-grade. Static buffer for read, no pid reaping, no
// O_NONBLOCK. Enough to prove the PTY pipeline works end-to-end
// for the hexa-only AI-native terminal prerequisite.
//
// 2026-04-11

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <util.h>     // openpty, forkpty (macOS / BSD)
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <sys/wait.h>
#include <termios.h>
#include <poll.h>

// Spawn /bin/echo hello-from-pty under a new PTY. Hardcoded cmd for
// first-light (avoids extern string-arg type inference). Returns
// master fd on success, -1 on failure. Child is left unreaped —
// acceptable for smoke where the parent exits immediately after.
long hexa_pty_spawn_echo(void) {
    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, NULL);
    if (pid < 0) return -1;
    if (pid == 0) {
        execl("/bin/echo", "echo", "hello-from-pty", (char*)NULL);
        _exit(127);
    }
    return (long)master;
}

// Read up to 1023 bytes from fd into a static buffer. Returns a
// pointer to the null-terminated buffer cast to long so hexa can
// treat it as a string. Static = NOT thread-safe, fine for smoke.
static char hexa_pty_readbuf[1024];
long hexa_pty_read_static(long fd) {
    ssize_t n = read((int)fd, hexa_pty_readbuf, sizeof(hexa_pty_readbuf) - 1);
    if (n <= 0) {
        hexa_pty_readbuf[0] = '\0';
        return (long)hexa_pty_readbuf;
    }
    // Strip trailing \r\n/\n for cleaner println output.
    while (n > 0 && (hexa_pty_readbuf[n-1] == '\n' || hexa_pty_readbuf[n-1] == '\r')) {
        n--;
    }
    hexa_pty_readbuf[n] = '\0';
    return (long)hexa_pty_readbuf;
}

long hexa_pty_close_fd(long fd) {
    return (long)close((int)fd);
}

// Print the static read buffer to stdout with a visible prefix.
// Returns the number of bytes in the buffer (strlen). Gives hexa
// side a way to observe PTY output without needing string-typed
// return values from extern fn.
long hexa_pty_puts_buf(void) {
    long n = (long)strlen(hexa_pty_readbuf);
    fprintf(stdout, "[pty_smoke] child said: \"%s\" (%ld bytes)\n",
            hexa_pty_readbuf, n);
    fflush(stdout);
    return n;
}

// ── Terminal 선행작업 #2: termios binding ──────────────────────
// Open a fresh PTY (no fork). Returns master fd on success. Slave
// fd is kept open internally so tcgetattr/tcsetattr on master stays
// valid; the slave is closed by hexa_term_release_pty().
static int hexa_term_slave_fd = -1;
long hexa_term_open_pty(void) {
    int m, s;
    if (openpty(&m, &s, NULL, NULL, NULL) < 0) return -1;
    hexa_term_slave_fd = s;
    return (long)m;
}
long hexa_term_release_pty(long master) {
    if (hexa_term_slave_fd >= 0) {
        close(hexa_term_slave_fd);
        hexa_term_slave_fd = -1;
    }
    return (long)close((int)master);
}

// Save termios of fd into static slot. Returns 0 on success, -1 on fail.
static struct termios hexa_term_saved;
static int hexa_term_saved_valid = 0;
long hexa_term_save(long fd) {
    if (tcgetattr((int)fd, &hexa_term_saved) < 0) return -1;
    hexa_term_saved_valid = 1;
    return 0;
}

// Return c_lflag as a long so hexa can probe the current mode.
// ICANON is typically 0x00000100 on macOS (tcsh-compatible).
long hexa_term_lflag(long fd) {
    struct termios t;
    if (tcgetattr((int)fd, &t) < 0) return -1;
    return (long)t.c_lflag;
}

// Apply raw mode via cfmakeraw.
long hexa_term_set_raw(long fd) {
    struct termios t;
    if (tcgetattr((int)fd, &t) < 0) return -1;
    cfmakeraw(&t);
    if (tcsetattr((int)fd, TCSANOW, &t) < 0) return -1;
    return 0;
}

// Apply cbreak mode (ICANON off, ECHO off, everything else cooked).
// Typical first step for a real terminal emulator.
long hexa_term_set_cbreak(long fd) {
    struct termios t;
    if (tcgetattr((int)fd, &t) < 0) return -1;
    t.c_lflag &= ~(ICANON | ECHO);
    t.c_cc[VMIN] = 1;
    t.c_cc[VTIME] = 0;
    if (tcsetattr((int)fd, TCSANOW, &t) < 0) return -1;
    return 0;
}

// Restore saved termios. Paired with hexa_term_save.
long hexa_term_restore(long fd) {
    if (!hexa_term_saved_valid) return -1;
    if (tcsetattr((int)fd, TCSANOW, &hexa_term_saved) < 0) return -1;
    return 0;
}

// Return ICANON bit of current c_lflag (0 or non-zero) for easy asserts.
long hexa_term_icanon_bit(long fd) {
    struct termios t;
    if (tcgetattr((int)fd, &t) < 0) return -1;
    return (long)(t.c_lflag & ICANON);
}

// ── Terminal 선행작업 #3: shell loop primitives ────────────────
// Spawn /bin/sh -i (interactive) under a new PTY. Returns master fd.
// Caller must reap the child via hexa_sh_reap. Child pid is stashed.
static pid_t hexa_sh_child_pid = -1;
long hexa_sh_spawn(void) {
    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, NULL);
    if (pid < 0) return -1;
    if (pid == 0) {
        // Quiet shell: PS1 empty so no prompt noise in the smoke output.
        setenv("PS1", "", 1);
        execl("/bin/sh", "sh", (char*)NULL);
        _exit(127);
    }
    hexa_sh_child_pid = pid;
    return (long)master;
}

// Write a string to a fd. For smoke usage — we encode the command
// as a static buffer index to avoid extern string args (build_c.hexa
// type inference limitation for this harness). See hexa_sh_cmd_N.
// Returns bytes written, -1 on error.
static const char* hexa_sh_canned[] = {
    "echo hexa-term\n",        // 0
    "exit\n",                  // 1
    "echo 1+1=$((1+1))\n",     // 2
    "echo void-app-entry-ok\n", // 3
    "echo interactive-ok\n",   // 4
    NULL
};
long hexa_sh_write_canned(long fd, long idx) {
    if (idx < 0 || idx > 4) return -1;
    const char* s = hexa_sh_canned[idx];
    return (long)write((int)fd, s, strlen(s));
}

// Poll a single fd for POLLIN with a timeout in ms. Returns >0 if
// readable, 0 on timeout, -1 on error.
long hexa_sh_poll(long fd, long timeout_ms) {
    struct pollfd pfd;
    pfd.fd = (int)fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int r = poll(&pfd, 1, (int)timeout_ms);
    if (r < 0) return -1;
    if (r == 0) return 0;
    return (pfd.revents & POLLIN) ? 1 : 0;
}

// Accumulated output buffer for the shell smoke. The loop reads
// into this via hexa_sh_append_read, then hexa checks substring
// presence via hexa_sh_contains.
static char hexa_sh_accum[8192];
static long hexa_sh_accum_len = 0;
void hexa_sh_reset_accum(void) {
    hexa_sh_accum[0] = '\0';
    hexa_sh_accum_len = 0;
}
// Read available bytes from fd into the accumulator. Returns bytes
// appended (0 = EOF, -1 on error, -2 on overflow).
long hexa_sh_append_read(long fd) {
    long cap = (long)sizeof(hexa_sh_accum) - 1 - hexa_sh_accum_len;
    if (cap <= 0) return -2;
    ssize_t n = read((int)fd, hexa_sh_accum + hexa_sh_accum_len, (size_t)cap);
    if (n < 0) {
        if (errno == EAGAIN || errno == EINTR) return 0;
        return -1;
    }
    hexa_sh_accum_len += n;
    hexa_sh_accum[hexa_sh_accum_len] = '\0';
    return (long)n;
}

// Return 1 if the accumulator contains the canned needle #idx.
// Needles mirror hexa_sh_canned output expectations.
static const char* hexa_sh_needles[] = {
    "hexa-term",           // 0 — from "echo hexa-term"
    "1+1=2",               // 1 — from the arithmetic canned cmd
    "void-app-entry-ok",   // 2 — from "echo void-app-entry-ok"
    "interactive-ok",      // 3 — from "echo interactive-ok"
    NULL
};
long hexa_sh_accum_contains(long idx) {
    if (idx < 0 || idx > 3) return -1;
    const char* needle = hexa_sh_needles[idx];
    return strstr(hexa_sh_accum, needle) ? 1 : 0;
}
long hexa_sh_accum_len_q(void) { return hexa_sh_accum_len; }

// Dump the accumulator to stdout with a prefix. Handy for smoke log.
long hexa_sh_dump_accum(void) {
    fprintf(stdout, "[sh_smoke] ── accumulator (%ld bytes) ──\n",
            hexa_sh_accum_len);
    fwrite(hexa_sh_accum, 1, (size_t)hexa_sh_accum_len, stdout);
    if (hexa_sh_accum_len > 0 && hexa_sh_accum[hexa_sh_accum_len-1] != '\n') {
        fputc('\n', stdout);
    }
    fprintf(stdout, "[sh_smoke] ── end accumulator ──\n");
    fflush(stdout);
    return hexa_sh_accum_len;
}

// Wait for the shell child to exit, return exit status (waitpid).
long hexa_sh_reap(void) {
    if (hexa_sh_child_pid <= 0) return -1;
    int status = 0;
    pid_t r = waitpid(hexa_sh_child_pid, &status, 0);
    hexa_sh_child_pid = -1;
    if (r < 0) return -1;
    return (long)(WIFEXITED(status) ? WEXITSTATUS(status) : -1);
}

// Write a single byte to a fd. Used by the interactive event loop
// to forward key events from AppKit to the PTY master.
long hexa_sh_write_byte(long fd, long byte_val) {
    char c = (char)byte_val;
    return (long)write((int)fd, &c, 1);
}

// ── Terminal 선행작업 #4: bidirectional forwarding primitives ──
// Forward all bytes from parent's stdin (fd 0) to the PTY master.
// Blocks until stdin EOF. Works with pipe stdin. Returns total
// bytes forwarded on success, -1 on write error.
long hexa_term_pipe_stdin_to_master(long master) {
    char buf[4096];
    long total = 0;
    for (;;) {
        ssize_t n = read(0, buf, sizeof(buf));
        if (n == 0) break;                 // EOF
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        ssize_t off = 0;
        while (off < n) {
            ssize_t w = write((int)master, buf + off, (size_t)(n - off));
            if (w <= 0) {
                if (w < 0 && errno == EINTR) continue;
                return -1;
            }
            off += w;
        }
        total += (long)n;
    }
    return total;
}

// Drain master until `timeout_ms` passes with no new data. Each
// available chunk is appended to the shared hexa_sh_accum buffer
// (reused from sh_smoke) so the hexa side can strstr-check it.
// Returns total bytes drained.
long hexa_term_drain_master(long master, long timeout_ms) {
    long total = 0;
    for (;;) {
        struct pollfd pfd;
        pfd.fd = (int)master;
        pfd.events = POLLIN;
        pfd.revents = 0;
        int r = poll(&pfd, 1, (int)timeout_ms);
        if (r <= 0) break;  // timeout or error
        if (!(pfd.revents & POLLIN)) break;
        long n = hexa_sh_append_read(master);
        if (n <= 0) break;  // EOF or error
        total += n;
    }
    return total;
}

// Return 1 if accum contains the 'hello-term' probe needle, else 0.
// Reused by term_v0 smoke.
long hexa_term_accum_has_hello_term(void) {
    return strstr(hexa_sh_accum, "hello-term") ? 1 : 0;
}

// Byte-at accessor so hexa side can iterate the accumulator content
// directly (feeding into VT parser + screen buffer). Returns the
// unsigned byte value 0..255, or -1 if idx is out of range.
long hexa_sh_accum_byte_at(long idx) {
    if (idx < 0 || idx >= hexa_sh_accum_len) return -1;
    return (long)(unsigned char)hexa_sh_accum[idx];
}

// ══════════════════════════════════════════════════════════════════
// void_main.hexa API — production terminal
// ══════════════════════════════════════════════════════════════════

long hexa_pty_spawn_login_shell(void) {
    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, NULL);
    if (pid < 0) return -1;
    if (pid == 0) {
        setenv("TERM", "xterm-256color", 1);
        char *shell = getenv("SHELL");
        if (!shell) shell = "/bin/sh";
        execl(shell, shell, "-l", (char*)NULL);
        _exit(127);
    }
    hexa_sh_child_pid = pid;
    int flags = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, flags | O_NONBLOCK);
    return (long)master;
}

#define PTY_READ_BUF_SIZE 65536
static char g_pty_read_buf[PTY_READ_BUF_SIZE];
static int g_pty_read_len = 0;

long hexa_pty_poll_read(long fd, long timeout_ms) {
    struct pollfd pfd;
    pfd.fd = (int)fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int ret = poll(&pfd, 1, (int)timeout_ms);
    if (ret <= 0 || !(pfd.revents & POLLIN)) {
        g_pty_read_len = 0;
        return 0;
    }
    g_pty_read_len = (int)read((int)fd, g_pty_read_buf, PTY_READ_BUF_SIZE - 1);
    if (g_pty_read_len < 0) g_pty_read_len = 0;
    g_pty_read_buf[g_pty_read_len] = '\0';

    // Alternate-screen workaround — hexa's VT parser doesn't implement
    // xterm's alt screen buffer (\x1b[?1049h/l and ?1047h/l), so full-
    // screen TUIs like `claude`, vim, htop paint on top of the previous
    // shell's output, causing the "Claude Code welcome overlapping the
    // cl selection table" ghosting the user hit. Rewrite the switch
    // sequences in place with a clear-screen + cursor-home so the TUI
    // starts from a blank canvas. Both are 8 bytes, same length, so the
    // rewrite is a straight memcpy with no length change.
    //   \x1b[?1049h  → \x1b[2J\x1b[1H
    //   \x1b[?1049l  → \x1b[2J\x1b[1H
    //   \x1b[?1047h  → \x1b[2J\x1b[1H
    //   \x1b[?1047l  → \x1b[2J\x1b[1H
    // A sequence split across two read() calls is not handled; hexa's
    // VT parser will eat the unknown CSI and the next read's payload
    // may land on the old buffer for one frame.
    for (int i = 0; i + 7 < g_pty_read_len; i++) {
        if (g_pty_read_buf[i]     == '\x1b' &&
            g_pty_read_buf[i + 1] == '['    &&
            g_pty_read_buf[i + 2] == '?'    &&
            g_pty_read_buf[i + 3] == '1'    &&
            g_pty_read_buf[i + 4] == '0'    &&
            g_pty_read_buf[i + 5] == '4'    &&
            (g_pty_read_buf[i + 6] == '9' || g_pty_read_buf[i + 6] == '7') &&
            (g_pty_read_buf[i + 7] == 'h' || g_pty_read_buf[i + 7] == 'l')) {
            memcpy(&g_pty_read_buf[i], "\x1b[2J\x1b[1H", 8);
            i += 7; // skip past the replacement (loop increments to 8)
        }
    }

    return (long)g_pty_read_len;
}

long hexa_pty_read_byte(long idx) {
    if (idx < 0 || idx >= g_pty_read_len) return -1;
    return (long)(unsigned char)g_pty_read_buf[idx];
}

// Returns 1 if VOID_TEST env var is set (test mode).
long hexa_check_test_mode(void) {
    return getenv("VOID_TEST") ? 1 : 0;
}

// PTY resize via ioctl TIOCSWINSZ
#include <sys/ioctl.h>
long hexa_pty_resize(long fd, long rows, long cols) {
    struct winsize ws;
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    return (long)ioctl((int)fd, TIOCSWINSZ, &ws);
}

// libc wrappers (hexa build_c adds hexa_user_ prefix to non-hexa_ names)
long hexa_mem_alloc(long size) {
    return (long)(uintptr_t)malloc((size_t)size);
}
void hexa_mem_free(long ptr) {
    free((void*)(uintptr_t)ptr);
}
long hexa_fd_write(long fd, long buf, long n) {
    return (long)write((int)fd, (void*)(uintptr_t)buf, (size_t)n);
}
long hexa_sleep_us(long us) {
    usleep((useconds_t)us);
    return 0;
}
