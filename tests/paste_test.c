// tests/paste_test.c — standalone harness for bracketed-paste helpers.
//
// Runs in background (no TTY, no GUI). Links against src/paste_util.c
// only. Exits 0 on full green, non-zero on first failure with a
// diagnostic line. Wired into scripts/build_void.sh so every build
// that promotes /tmp/void_term must also pass these.
//
// Test matrix:
//   T1  zero-length payload             — no bytes written
//   T2  short payload (< PASTE_CHUNK)   — start + body + end, single pass
//   T3  mid payload (= PASTE_CHUNK)     — exact one-chunk boundary
//   T4  large payload (5× PASTE_CHUNK)  — all bytes delivered, wrapped
//   T5  invalid fd                      — no crash, no bytes read back
//   T6  null buf                        — no crash
//   T7  throughput (1MB under 2 sec)    — paste lag guard

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <errno.h>

extern void   pty_inject_bracketed_paste(int fd, const char *buf, size_t n);
extern size_t paste_write_chunked      (int fd, const char *buf, size_t n);

#define START "\x1b[200~"
#define END   "\x1b[201~"
#define START_LEN 6
#define END_LEN   6

static int pass = 0;
static int fail = 0;

static void check(int cond, const char *name, const char *msg) {
    if (cond) { printf("[paste-test] %-30s PASS\n", name); pass++; }
    else      { printf("[paste-test] %-30s FAIL — %s\n", name, msg); fail++; }
}

// drain_pipe_nonblock: read everything currently available on `rfd`
// into `out` up to `cap`. Returns bytes read. Non-blocking so tests
// terminate even if writer stalled.
static size_t drain_pipe_nonblock(int rfd, char *out, size_t cap) {
    int fl = fcntl(rfd, F_GETFL, 0);
    fcntl(rfd, F_SETFL, fl | O_NONBLOCK);
    size_t total = 0;
    while (total < cap) {
        ssize_t r = read(rfd, out + total, cap - total);
        if (r > 0) { total += (size_t)r; continue; }
        if (r < 0 && errno == EAGAIN) break;
        break;
    }
    return total;
}

// make_pipe_big: pipe() only. macOS has no F_SETPIPE_SZ, but the
// default ~64KB buffer is plenty for tests under PASTE_CHUNK × 5
// (=20KB). For the 1MB throughput test we spawn a reader child that
// drains concurrently, so pipe size never matters there.
static int make_pipe_big(int fds[2]) {
    return pipe(fds);
}

static void t_zero(void) {
    int fds[2]; make_pipe_big(fds);
    pty_inject_bracketed_paste(fds[1], "", 0);
    char buf[64];
    size_t n = drain_pipe_nonblock(fds[0], buf, sizeof(buf));
    check(n == 0, "T1 zero-length", "expected no write");
    close(fds[0]); close(fds[1]);
}

static void t_short(void) {
    int fds[2]; make_pipe_big(fds);
    const char *payload = "hello world";
    size_t plen = strlen(payload);
    pty_inject_bracketed_paste(fds[1], payload, plen);
    char buf[128];
    size_t n = drain_pipe_nonblock(fds[0], buf, sizeof(buf));
    int ok = (n == START_LEN + plen + END_LEN)
          && memcmp(buf, START, START_LEN) == 0
          && memcmp(buf + START_LEN, payload, plen) == 0
          && memcmp(buf + START_LEN + plen, END, END_LEN) == 0;
    check(ok, "T2 short payload",
          ok ? "" : "wrap/body mismatch");
    close(fds[0]); close(fds[1]);
}

static void t_exact_chunk(void) {
    int fds[2]; make_pipe_big(fds);
    enum { CHUNK = 4096 };
    char *payload = malloc(CHUNK);
    for (int i = 0; i < CHUNK; i++) payload[i] = (char)('A' + (i % 26));
    pty_inject_bracketed_paste(fds[1], payload, CHUNK);
    char *out = malloc(CHUNK + 64);
    size_t n = drain_pipe_nonblock(fds[0], out, CHUNK + 64);
    int ok = (n == START_LEN + CHUNK + END_LEN)
          && memcmp(out, START, START_LEN) == 0
          && memcmp(out + START_LEN, payload, CHUNK) == 0
          && memcmp(out + START_LEN + CHUNK, END, END_LEN) == 0;
    check(ok, "T3 exact 4K chunk",
          ok ? "" : "one-chunk boundary incorrect");
    free(payload); free(out);
    close(fds[0]); close(fds[1]);
}

// For large payloads we need a reader thread OR we drain between
// chunks. Simpler: use a larger pipe (mac default ~64KB) and keep
// payload under that. Test with 20KB which is ~5 chunks.
static void t_large(void) {
    int fds[2]; make_pipe_big(fds);
    enum { N = 20480 };
    char *payload = malloc(N);
    for (int i = 0; i < N; i++) payload[i] = (char)(i & 0xFF);
    pty_inject_bracketed_paste(fds[1], payload, N);
    char *out = malloc(N + 64);
    size_t n = drain_pipe_nonblock(fds[0], out, N + 64);
    int ok = (n == START_LEN + N + END_LEN)
          && memcmp(out, START, START_LEN) == 0
          && memcmp(out + START_LEN, payload, N) == 0
          && memcmp(out + START_LEN + N, END, END_LEN) == 0;
    check(ok, "T4 large (20KB, 5 chunks)",
          ok ? "" : "large-payload round-trip mismatch");
    free(payload); free(out);
    close(fds[0]); close(fds[1]);
}

static void t_invalid_fd(void) {
    // -1 fd: must not crash, must not hang.
    pty_inject_bracketed_paste(-1, "hello", 5);
    check(1, "T5 invalid fd (-1)", "");
}

static void t_null_buf(void) {
    int fds[2]; make_pipe_big(fds);
    pty_inject_bracketed_paste(fds[1], NULL, 10);
    char buf[16];
    size_t n = drain_pipe_nonblock(fds[0], buf, sizeof(buf));
    check(n == 0, "T6 null buf", "expected no write");
    close(fds[0]); close(fds[1]);
}

// t_throughput: paste 1MB in a loop with a child reader. Ensures the
// chunk+yield policy doesn't tank throughput. Threshold 2s is a
// generous ceiling — normal should complete in < 500ms.
static void t_throughput(void) {
    int fds[2]; make_pipe_big(fds);
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[1]);
        char chunk[65536];
        while (read(fds[0], chunk, sizeof(chunk)) > 0) { /* drain */ }
        close(fds[0]);
        _exit(0);
    }
    close(fds[0]);
    enum { N = 1 << 20 }; /* 1 MB */
    char *payload = malloc(N);
    memset(payload, 'x', N);
    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    pty_inject_bracketed_paste(fds[1], payload, N);
    gettimeofday(&t1, NULL);
    close(fds[1]);
    waitpid(pid, NULL, 0);
    double secs = (t1.tv_sec - t0.tv_sec) + (t1.tv_usec - t0.tv_usec) / 1e6;
    int ok = secs < 2.0;
    char msg[64];
    snprintf(msg, sizeof(msg), "took %.2fs (>2.0s ceiling)", secs);
    printf("[paste-test] T7 throughput 1MB       %s — %.3fs\n",
           ok ? "PASS" : "FAIL", secs);
    if (ok) pass++; else { fail++; (void)msg; }
    free(payload);
}

int main(void) {
    printf("[paste-test] === START ===\n");
    t_zero();
    t_short();
    t_exact_chunk();
    t_large();
    t_invalid_fd();
    t_null_buf();
    t_throughput();
    printf("[paste-test] %d/%d passed\n", pass, pass + fail);
    if (fail == 0) printf("[paste-test] === ALL PASTE TESTS PASS ===\n");
    return fail == 0 ? 0 : 1;
}
