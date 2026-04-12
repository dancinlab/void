// void_harness — integration test harness for void terminal
//
// Drives void_server via its Unix socket protocol:
//   SPAWN a session → write to PTY → ATTACH to read grid → verify.
// Usage: void_harness [test-name]   (no args = run all)
//
// Build: cc -O2 -o void_harness src/void_harness.c

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ioctl.h>
#include <poll.h>
#include <errno.h>

// ── protocol constants (mirror void_server.c) ──

#define VS_MAGIC   0x31525356u
#define VS_SPAWN   1
#define VS_ATTACH  2
#define VS_DETACH  3
#define VS_LIST    4
#define VS_KILL    5
#define VS_SOCK    "/tmp/void_server.sock"

#define GRID_ROWS  200
#define GRID_COLS  400
#define SECT_LINES 64
#define N_SECTIONS ((GRID_ROWS + SECT_LINES - 1) / SECT_LINES)

typedef struct { uint16_t ch, _pad; int32_t fg, bg, flags; } Cell;

// ── socket helpers ──

static int sock_connect(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return -1; }
    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    strncpy(addr.sun_path, VS_SOCK, sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("connect");
        close(fd);
        return -1;
    }
    return fd;
}

static int read_exact(int fd, void *buf, size_t n) {
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, (char *)buf + got, n - got);
        if (r <= 0) { if (r < 0 && errno == EINTR) continue; return -1; }
        got += (size_t)r;
    }
    return 0;
}

static int write_exact(int fd, const void *buf, size_t n) {
    size_t sent = 0;
    while (sent < n) {
        ssize_t w = write(fd, (const char *)buf + sent, n - sent);
        if (w <= 0) { if (w < 0 && errno == EINTR) continue; return -1; }
        sent += (size_t)w;
    }
    return 0;
}

static int send_cmd(int fd, uint32_t cmd, const void *body, uint32_t blen) {
    uint32_t hdr[3] = { VS_MAGIC, cmd, blen };
    if (write_exact(fd, hdr, 12) != 0) return -1;
    if (blen > 0 && write_exact(fd, body, blen) != 0) return -1;
    return 0;
}

// Receive response. *out_status = status code, *out_body = malloc'd body
// (caller frees), *out_blen = body length. Returns passed fd or -1.
static int recv_response(int fd, uint32_t *out_status,
                         char **out_body, uint32_t *out_blen) {
    // Use recvmsg to receive SCM_RIGHTS fd
    uint32_t hdr[3];
    struct msghdr msg = {0};
    struct iovec iov = { .iov_base = hdr, .iov_len = sizeof(hdr) };
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    char ctrl[CMSG_SPACE(sizeof(int))];
    memset(ctrl, 0, sizeof(ctrl));
    msg.msg_control = ctrl;
    msg.msg_controllen = sizeof(ctrl);

    ssize_t r = recvmsg(fd, &msg, 0);
    if (r < (ssize_t)sizeof(hdr)) return -1;
    if (hdr[0] != VS_MAGIC) return -1;

    *out_status = hdr[1];
    *out_blen = hdr[2];

    int passed_fd = -1;
    struct cmsghdr *cm = CMSG_FIRSTHDR(&msg);
    if (cm && cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_RIGHTS) {
        memcpy(&passed_fd, CMSG_DATA(cm), sizeof(int));
    }

    *out_body = NULL;
    if (*out_blen > 0) {
        *out_body = (char *)malloc(*out_blen);
        if (!*out_body) return -1;
        // recvmsg may have delivered some body bytes already
        size_t extra = (size_t)r - sizeof(hdr);
        if (extra > *out_blen) extra = *out_blen;
        if (extra > 0) {
            // hdr was 12 bytes; extra bytes came after in the same read
            // but iov only covered hdr, so extra should be 0 normally.
        }
        if (read_exact(fd, *out_body, *out_blen) != 0) {
            free(*out_body); *out_body = NULL;
            return -1;
        }
    }
    return passed_fd;
}

// ── high-level operations ──

// SPAWN a session, returns PTY fd. Fills session_id[32].
static int harness_spawn(char *session_id, const char *label,
                         const char *cwd, int rows, int cols) {
    int sock = sock_connect();
    if (sock < 0) return -1;

    // body: label[64] + cwd[512] + cmd[512] + rows:u16 + cols:u16
    char body[64 + 512 + 512 + 4];
    memset(body, 0, sizeof(body));
    snprintf(body, 64, "%s", label);
    snprintf(body + 64, 512, "%s", cwd);
    // Use plain /bin/sh with a clean env to avoid zsh escape
    // sequences confusing the server's naive grid parser.
    // ENV=/dev/null suppresses .profile; PS1 gives a known prompt.
    snprintf(body + 64 + 512, 512, "ENV=/dev/null PS1='$ ' exec /bin/sh");
    uint16_t r16 = (uint16_t)rows, c16 = (uint16_t)cols;
    memcpy(body + 64 + 512 + 512, &r16, 2);
    memcpy(body + 64 + 512 + 512 + 2, &c16, 2);

    if (send_cmd(sock, VS_SPAWN, body, sizeof(body)) != 0) {
        close(sock); return -1;
    }

    uint32_t status, blen;
    char *resp;
    int pty_fd = recv_response(sock, &status, &resp, &blen);
    if (status != 0 || blen < 32) {
        free(resp); close(sock);
        fprintf(stderr, "SPAWN failed: status=%u\n", status);
        return -1;
    }
    memcpy(session_id, resp, 32);
    free(resp);
    close(sock);
    return pty_fd;
}

// ATTACH to read grid. Returns malloc'd Cell grid (rows*cols cells).
// Caller frees. Also returns a new PTY fd (or same if already held).
static Cell *harness_attach(const char *session_id, int *out_rows, int *out_cols) {
    int sock = sock_connect();
    if (sock < 0) return NULL;

    // body: id[32] + n_hashes:u32 (0 = get full grid)
    char body[36];
    memcpy(body, session_id, 32);
    uint32_t zero = 0;
    memcpy(body + 32, &zero, 4);

    if (send_cmd(sock, VS_ATTACH, body, 36) != 0) {
        close(sock); return NULL;
    }

    uint32_t status, blen;
    char *resp;
    int fd = recv_response(sock, &status, &resp, &blen);
    if (fd >= 0) close(fd); // don't need the PTY fd here

    if (status != 0 || !resp || blen < 8) {
        free(resp); close(sock);
        fprintf(stderr, "ATTACH failed: status=%u\n", status);
        return NULL;
    }

    // Parse: rows:u16 + cols:u16 + n_sections:u32
    uint16_t rows, cols;
    uint32_t n_sect;
    memcpy(&rows, resp, 2);
    memcpy(&cols, resp + 2, 2);
    memcpy(&n_sect, resp + 4, 4);
    *out_rows = rows;
    *out_cols = cols;

    Cell *grid = (Cell *)calloc((size_t)rows * cols, sizeof(Cell));
    if (!grid) { free(resp); close(sock); return NULL; }

    // Parse sections
    size_t off = 8;
    for (uint32_t s = 0; s < n_sect && off < blen; s++) {
        if (off + 16 > blen) break;
        uint32_t idx, bytes;
        uint64_t hash;
        memcpy(&idx, resp + off, 4);   off += 4;
        memcpy(&bytes, resp + off, 4); off += 4;
        memcpy(&hash, resp + off, 8);  off += 8;
        if (bytes > 0) {
            int row0 = (int)idx * SECT_LINES;
            for (int dr = 0; dr < SECT_LINES; dr++) {
                int r = row0 + dr;
                size_t row_bytes = (size_t)cols * sizeof(Cell);
                if (off + row_bytes > blen) break;
                if (r < rows) {
                    memcpy(&grid[r * cols], resp + off, row_bytes);
                }
                off += row_bytes;
            }
        }
    }

    free(resp);
    close(sock);
    return grid;
}

// KILL a session
static void harness_kill(const char *session_id) {
    int sock = sock_connect();
    if (sock < 0) return;
    send_cmd(sock, VS_KILL, session_id, 32);
    uint32_t status, blen; char *resp;
    recv_response(sock, &status, &resp, &blen);
    free(resp);
    close(sock);
}

// ── grid inspection helpers ──

// Read a string from grid row (0-based). Returns static buffer.
static char *grid_row_text(const Cell *grid, int cols, int row) {
    static char buf[1024];
    int len = 0;
    for (int c = 0; c < cols && len < 1023; c++) {
        uint16_t ch = grid[row * cols + c].ch;
        if (ch == 0) ch = ' ';
        if (ch < 128) buf[len++] = (char)ch;
    }
    // trim trailing spaces
    while (len > 0 && buf[len - 1] == ' ') len--;
    buf[len] = 0;
    return buf;
}

// Check if any row contains the substring
static int grid_contains(const Cell *grid, int rows, int cols, const char *needle) {
    for (int r = 0; r < rows; r++) {
        char *line = grid_row_text(grid, cols, r);
        if (strstr(line, needle)) return r;
    }
    return -1;
}

// Print first N non-empty rows
static void grid_dump(const Cell *grid, int rows, int cols, int max_lines) {
    int printed = 0;
    for (int r = 0; r < rows && printed < max_lines; r++) {
        char *line = grid_row_text(grid, cols, r);
        if (line[0]) {
            printf("  [%3d] %s\n", r, line);
            printed++;
        }
    }
}

// Poll grid until needle appears or timeout (ms). Returns row or -1.
static int grid_wait(const char *sid, const char *needle, int timeout_ms) {
    int elapsed = 0;
    int step = 200; // ms
    while (elapsed < timeout_ms) {
        usleep(step * 1000);
        elapsed += step;
        int rows, cols;
        Cell *grid = harness_attach(sid, &rows, &cols);
        if (!grid) continue;
        int found = grid_contains(grid, rows, cols, needle);
        free(grid);
        if (found >= 0) return found;
    }
    return -1;
}

// ── test cases ──

typedef struct {
    const char *name;
    int (*fn)(void);
} TestCase;

static int g_pass = 0, g_fail = 0;

#define ASSERT_TRUE(expr, msg) do { \
    if (!(expr)) { \
        printf("  FAIL: %s\n", msg); \
        return 1; \
    } \
} while(0)

// Write string to PTY with full delivery
static void pty_type(int pty, const char *s) {
    write_exact(pty, s, strlen(s));
}

// T1: spawn + echo + verify grid
static int test_echo(void) {
    char sid[32];
    int pty = harness_spawn(sid, "test-echo", "/tmp", 24, 80);
    ASSERT_TRUE(pty >= 0, "spawn failed");

    // Wait for shell prompt (trim strips trailing space, match "$")
    int ready = grid_wait(sid, "$", 5000);
    ASSERT_TRUE(ready >= 0, "shell prompt never appeared");

    pty_type(pty, "echo HELLO_VOID\n");

    int found = grid_wait(sid, "HELLO_VOID", 5000);
    if (found < 0) {
        int rows, cols;
        Cell *grid = harness_attach(sid, &rows, &cols);
        if (grid) {
            printf("\n  Grid dump (all non-empty):\n");
            grid_dump(grid, rows, cols, 24);
            free(grid);
        }
    }
    close(pty);
    harness_kill(sid);
    ASSERT_TRUE(found >= 0, "HELLO_VOID not found in grid");
    return 0;
}

// T2: ls -1 output (one per line, no tabs)
static int test_ls(void) {
    char sid[32];
    int pty = harness_spawn(sid, "test-ls", "/", 24, 80);
    ASSERT_TRUE(pty >= 0, "spawn failed");
    grid_wait(sid, "$", 3000);

    pty_type(pty, "ls -1 /\n");

    int found = grid_wait(sid, "usr", 5000);
    if (found < 0) {
        int rows, cols;
        Cell *grid = harness_attach(sid, &rows, &cols);
        if (grid) { printf("\n  Grid dump:\n"); grid_dump(grid, rows, cols, 15); free(grid); }
    }
    close(pty);
    harness_kill(sid);
    ASSERT_TRUE(found >= 0, "'usr' not found in ls -1 / output");
    return 0;
}

// T3: printf exact string
static int test_cursor(void) {
    char sid[32];
    int pty = harness_spawn(sid, "test-cursor", "/tmp", 24, 80);
    ASSERT_TRUE(pty >= 0, "spawn failed");
    grid_wait(sid, "$", 5000);

    pty_type(pty, "printf 'XYZ_MARKER\\n'\n");

    int found = grid_wait(sid, "XYZ_MARKER", 5000);
    if (found < 0) {
        int rows, cols;
        Cell *grid = harness_attach(sid, &rows, &cols);
        if (grid) { printf("\n  Grid dump:\n"); grid_dump(grid, rows, cols, 15); free(grid); }
    }
    close(pty);
    harness_kill(sid);
    ASSERT_TRUE(found >= 0, "'XYZ_MARKER' not found in grid");
    return 0;
}

// T4: multi-line output
static int test_multiline(void) {
    char sid[32];
    int pty = harness_spawn(sid, "test-multi", "/tmp", 24, 80);
    ASSERT_TRUE(pty >= 0, "spawn failed");
    grid_wait(sid, "$", 5000);

    pty_type(pty, "for i in 1 2 3 4 5; do echo LINE_$i; done\n");

    int f5 = grid_wait(sid, "LINE_5", 5000);
    if (f5 >= 0) {
        int rows, cols;
        Cell *grid = harness_attach(sid, &rows, &cols);
        if (grid) {
            int f1 = grid_contains(grid, rows, cols, "LINE_1");
            if (f1 < 0) { printf("\n  Grid dump:\n"); grid_dump(grid, rows, cols, 15); }
            free(grid);
            close(pty);
            harness_kill(sid);
            ASSERT_TRUE(f1 >= 0, "LINE_1 not found (scrolled off?)");
            return 0;
        }
    } else {
        int rows, cols;
        Cell *grid = harness_attach(sid, &rows, &cols);
        if (grid) { printf("\n  Grid dump:\n"); grid_dump(grid, rows, cols, 15); free(grid); }
    }
    close(pty);
    harness_kill(sid);
    ASSERT_TRUE(f5 >= 0, "LINE_5 not found");
    return 0;
}

// T5: session kill cleans up
static int test_kill(void) {
    char sid[32];
    int pty = harness_spawn(sid, "test-kill", "/tmp", 24, 80);
    ASSERT_TRUE(pty >= 0, "spawn failed");
    close(pty);

    harness_kill(sid);
    usleep(300000);

    int rows, cols;
    Cell *grid = harness_attach(sid, &rows, &cols);
    int dead = (grid == NULL);
    free(grid);
    ASSERT_TRUE(dead, "session should be gone after KILL");
    return 0;
}

// ── main ──

// T6: raw debug — no reads, same pattern as T2
static int test_debug(void) {
    char sid[32];
    int pty = harness_spawn(sid, "test-debug", "/tmp", 24, 80);
    ASSERT_TRUE(pty >= 0, "spawn failed");
    printf("\n");

    int ready = grid_wait(sid, "$", 5000);
    printf("  [debug] prompt ready: %s\n", ready >= 0 ? "YES" : "NO");

    // Test A: echo FIRST
    pty_type(pty, "echo FIRST_CMD\n");
    int fa = grid_wait(sid, "FIRST_CMD", 5000);
    printf("  [debug] echo FIRST_CMD: %s\n", fa >= 0 ? "YES" : "NO");

    // Test B: echo SECOND
    pty_type(pty, "echo SECOND_CMD\n");
    int found = grid_wait(sid, "SECOND_CMD", 5000);
    printf("  [debug] echo SECOND_CMD: %s\n", found >= 0 ? "YES" : "NO");

    // Dump grid regardless
    int rows, cols;
    Cell *grid = harness_attach(sid, &rows, &cols);
    if (grid) {
        printf("  [debug] grid:\n");
        grid_dump(grid, rows, cols, 15);
        free(grid);
    }

    close(pty);
    harness_kill(sid);
    ASSERT_TRUE(found >= 0, "SECOND_CMD not found in grid");
    return 0;
}

static TestCase tests[] = {
    { "debug",     test_debug },
    { "echo",      test_echo },
    { "ls",        test_ls },
    { "cursor",    test_cursor },
    { "multiline", test_multiline },
    { "kill",      test_kill },
};
#define N_TESTS (int)(sizeof(tests) / sizeof(tests[0]))

int main(int argc, char **argv) {
    const char *filter = argc > 1 ? argv[1] : NULL;

    printf("[void-harness] === INTEGRATION TEST START ===\n");
    printf("[void-harness] server: %s\n\n", VS_SOCK);

    for (int i = 0; i < N_TESTS; i++) {
        if (filter && !strstr(tests[i].name, filter)) continue;
        printf("[void-harness] T%d %s ... ", i + 1, tests[i].name);
        fflush(stdout);
        int rc = tests[i].fn();
        if (rc == 0) {
            printf("PASS\n");
            g_pass++;
        } else {
            g_fail++;
        }
    }

    printf("\n[void-harness] %d/%d passed\n", g_pass, g_pass + g_fail);
    if (g_fail > 0) {
        printf("[void-harness] FAILED\n");
        return 1;
    }
    printf("[void-harness] ALL PASS\n");
    return 0;
}
