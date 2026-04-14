// paste_util.c — bracketed-paste helpers shared by the terminal view
// and the C-level test harness. Pure C (no ObjC) so tests/paste_test.c
// can link this without pulling in Cocoa.
//
// Rationale for chunking:
//   A single large write() to the PTY master hands the whole payload
//   to the kernel in one go. Downstream apps with input-buffered echo
//   (Claude Code CLI, vim :i mode, REPLs) back-pressure against that
//   blast: their read() drains only what fits in their input buffer,
//   leaving the remainder sitting in the PTY until the next tick. If
//   they also do per-line processing (syntax highlight, completion),
//   the UI visibly freezes for hundreds of ms on 50KB+ pastes.
//   Splitting gives them room to breathe AND lets void's own event
//   loop process redraw ticks between chunks, so paste is smooth.

#include <unistd.h>
#include <stddef.h>
#include <sys/types.h>

// paste_write_chunked: write `n` bytes from `buf` to `fd` in chunks of
// at most PASTE_CHUNK, yielding between chunks when the payload is
// larger than one chunk. Returns bytes actually written.
size_t paste_write_chunked(int fd, const char *buf, size_t n) {
    const size_t PASTE_CHUNK = 4096;
    const useconds_t YIELD_US = 200;
    size_t off = 0;
    while (off < n) {
        size_t want = n - off;
        if (want > PASTE_CHUNK) want = PASTE_CHUNK;
        ssize_t w = write(fd, buf + off, want);
        if (w <= 0) break;
        off += (size_t)w;
        if (n > PASTE_CHUNK && off < n) usleep(YIELD_US);
    }
    return off;
}

// pty_inject_bracketed_paste: send `buf[0..n]` wrapped in DECSET 2004
// brackets (ESC[200~ ... ESC[201~). No-op for invalid fd, null buf, or
// zero length.
void pty_inject_bracketed_paste(int fd, const char *buf, size_t n) {
    if (fd < 0 || !buf || n == 0) return;
    static const char START[] = "\x1b[200~";
    static const char END[]   = "\x1b[201~";
    (void)write(fd, START, sizeof(START) - 1);
    (void)paste_write_chunked(fd, buf, n);
    (void)write(fd, END, sizeof(END) - 1);
}
