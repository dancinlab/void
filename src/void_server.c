// void-server — session supervisor daemon
//
// Owns PTY masters on behalf of void_term clients so that:
//   1. Processes (claude, shell, vim, etc.) survive client exit
//   2. Clients can re-attach to sessions across restarts
//   3. Hot-swap (void_term rebuild) is free — the PTY never closes
//   4. Crash resurrection — periodic checkpoints let us restore state
//      if the server itself dies (we reparent PTYs via launchd-ish trick)
//
// Wire protocol — length-prefixed binary over AF_UNIX/SOCK_STREAM at
//   /tmp/void_server.sock
//
//   Request frame:
//     uint32 magic = 'VSR1'
//     uint32 cmd   = VS_SPAWN | VS_ATTACH | VS_DETACH | VS_LIST | VS_KILL
//     uint32 body_len
//     bytes  body (command-specific)
//
//   Response frame:
//     uint32 magic = 'VSR1'
//     uint32 status = 0 success | nonzero errno-ish
//     uint32 body_len
//     bytes  body
//
//   SPAWN body:
//     char title[64]
//     char path[512]   (cwd; "" = inherit)
//     char cmd[512]    (cmd to run after cd; "" = default shell)
//     uint16 rows
//     uint16 cols
//   SPAWN response body:
//     char session_id[32]   (ULID-ish)
//     uint32 pty_fd_hint    (informational; real fd arrives via SCM_RIGHTS on the control msg)
//
//   ATTACH body:
//     char     session_id[32]
//     uint32   n_client_hashes            (0 = full snapshot, first-attach path)
//     uint64   client_hash[n_client_hashes] (per-section FNV64 the client already has)
//   ATTACH response body:
//     uint16   rows
//     uint16   cols
//     uint32   n_sections                 (total section count in this grid)
//     repeat n_sections times:
//       uint32 section_idx
//       uint32 section_bytes              (0 = unchanged, payload omitted)
//       uint64 server_hash                (live FNV64 for this section)
//       bytes  section_data               (SECTION_LINES * cols * sizeof(VsCell))
//     + the real PTY fd arrives via SCM_RIGHTS
//
//   DETACH body:
//     char session_id[32]
//   DETACH response: empty (session kept alive, client-side fd should be closed)
//
//   LIST body: empty
//   LIST response body:
//     uint32 n
//     repeated n times:
//       char session_id[32]
//       char label[64]
//       char cwd[256]
//       uint32 proc_count
//       repeated proc_count times:
//         char name[32]
//   KILL body: char session_id[32] — hard-kill the session (SIGTERM to pgrp)
//
// AI-native layers:
//   - Semantic label: derived from cwd tail + dominant child process name
//   - Process classifier: lookup table picks persistence strategy on detach
//   - Content-hashed state store: Merkle tree over 64-line sections, delta sync
//   - Checkpoint engine: periodic (every 5s) dump of grid + cursor to disk
//   - Crash resurrection: on server startup, scan ckpt dir for orphan sessions

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sys/uio.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/event.h>   // kqueue for binary watcher
#include <sys/time.h>
#include <util.h>        // forkpty
#include <libproc.h>
#include <sys/proc_info.h>
#include <time.h>
#include <pwd.h>
#include <dirent.h>

#define VS_MAGIC           0x31525356u  // 'VSR1' little-endian
#define VS_SPAWN           1
#define VS_ATTACH          2
#define VS_DETACH          3
#define VS_LIST            4
#define VS_KILL            5
#define VS_CHECKPOINT      6
#define VS_PING            7
#define VS_SOCK_PATH       "/tmp/void_server.sock"
#define VS_CKPT_DIR        "/tmp/void_server_ckpt"
#define VS_MAX_SESSIONS    64
#define VS_GRID_ROWS       200
#define VS_GRID_COLS       400
#define VS_SECTION_LINES   64   // Merkle section size
#define VS_MAX_CLIENTS     32
#define VS_READ_BUF_SIZE   65536

// Wire cell — same 16 bytes as sys_appkit.m TermCell
typedef struct {
    uint16_t ch;
    uint16_t _pad;
    int32_t  fg;
    int32_t  bg;
    int32_t  flags;
} VsCell;

// Session state held by the daemon
typedef struct {
    int     used;
    char    id[32];            // ULID-ish
    char    label[64];         // semantic label (e.g. "nexus-atlas-refactor")
    char    cwd[512];
    char    cmd_launched[512];
    pid_t   shell_pid;
    int     pty_fd;            // master held by server
    int     rows, cols;
    int     attached_client_fd;// -1 when nobody attached
    int     is_checkpoint_restored; // 1 if restored from ckpt w/o live PTY
    long    last_activity_ns;
    VsCell  grid[VS_GRID_ROWS * VS_GRID_COLS];
    int     cur_row, cur_col;
    // Per-section hash cache for Merkle delta sync. One hash per 64-line
    // block; recalc lazily when the section has been written since last hash.
    uint64_t section_hash[VS_GRID_ROWS / VS_SECTION_LINES + 1];
    int      section_dirty[VS_GRID_ROWS / VS_SECTION_LINES + 1];
    // Snapshot of the binary mtime (ns) at the moment this session was
    // last attached. Clients can diff this against current_binary_mtime
    // in LIST responses to know whether a hot-swap happened while they
    // were detached — if so, the client can trigger a clean reconnect.
    uint64_t last_attach_mtime;
} VsSession;

static VsSession g_sessions[VS_MAX_SESSIONS];
static int       g_sock_listen = -1;
static int       g_shutdown   = 0;
static long      g_last_ckpt_ns = 0;   // VS-07: last periodic checkpoint time
#define VS_CKPT_INTERVAL_NS (5L * 1000000000L)  // 5 seconds

// ── per-client state (VS-17 single-process refactor) ────────────────
//
// The fork-per-client model was replaced with a single-process select()
// loop so that the listener parent retains ownership of every PTY
// master fd. When a client dies (SIGKILL, crash, whatever), the
// listener simply drops its client slot — the shell's master fd stays
// open in this process and the shell keeps running until explicitly
// killed or the server itself dies. See VP-05.
#define VS_CLIENT_RECV_BUF_SIZE (1 << 20)

typedef struct {
    int      used;
    int      fd;                 // accepted socket
    // Frame assembly state — a complete request is hdr[3] followed by
    // hdr[2] bytes of body. We buffer partial reads because the socket
    // is non-blocking and may deliver a frame in many chunks.
    unsigned char recv_buf[VS_CLIENT_RECV_BUF_SIZE];
    size_t   recv_have;          // bytes currently held in recv_buf
} VsClient;

static VsClient g_clients[VS_MAX_CLIENTS];

static int alloc_client_slot(int fd) {
    for (int i = 0; i < VS_MAX_CLIENTS; i++) {
        if (!g_clients[i].used) {
            g_clients[i].used = 1;
            g_clients[i].fd   = fd;
            g_clients[i].recv_have = 0;
            return i;
        }
    }
    return -1;
}

static void free_client_slot(int idx) {
    if (idx < 0 || idx >= VS_MAX_CLIENTS) return;
    g_clients[idx].used = 0;
    g_clients[idx].fd   = -1;
    g_clients[idx].recv_have = 0;
}

static void set_nonblock(int fd) {
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl >= 0) fcntl(fd, F_SETFL, fl | O_NONBLOCK);
}

// ── binary watcher state ────────────────────────────────────────────
//
// kqueue-based EVFILT_VNODE watcher on the void_term binary path. When
// the auto-build hook replaces the binary, we want to log the swap so
// the server can prepare for clean reconnects (a future phase will also
// spawn a shadow void_term with --prewarm). If kqueue registration ever
// fails we fall back to polling stat() mtime every main-loop tick.
#define VS_BINWATCH_PATH "/Applications/VOID.app/Contents/MacOS/void_term"
#define VS_BINWATCH_LOG  "/tmp/void_server_binwatch.log"

static int  g_binwatch_kq = -1;
static int  g_binwatch_fd = -1;
static long g_binary_mtime_ns = 0;   // last observed mtime in ns
static int  g_binwatch_poll_fallback = 0;

// ── util ─────────────────────────────────────────────────────────────

static void die(const char *msg) {
    fprintf(stderr, "[void-server] fatal: %s: %s\n", msg, strerror(errno));
    exit(1);
}

static long now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)ts.tv_sec * 1000000000L + ts.tv_nsec;
}

// Simple ULID-ish id: 13-char timestamp + 6-char random — stable sort order.
static void gen_session_id(char out[32]) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    uint64_t ms = (uint64_t)ts.tv_sec * 1000ULL + ts.tv_nsec / 1000000ULL;
    static const char a[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    for (int i = 12; i >= 0; i--) { out[i] = a[ms & 0x1F]; ms >>= 5; }
    uint32_t r = (uint32_t)(ts.tv_nsec ^ getpid());
    for (int i = 13; i < 19; i++) { out[i] = a[r & 0x1F]; r >>= 5; }
    out[19] = 0;
}

// Fast non-cryptographic hash — FNV-1a 64. Good enough for delta sync.
static uint64_t fnv1a64(const void *data, size_t len) {
    uint64_t h = 0xcbf29ce484222325ULL;
    const unsigned char *p = (const unsigned char *)data;
    for (size_t i = 0; i < len; i++) {
        h ^= p[i];
        h *= 0x100000001b3ULL;
    }
    return h;
}

// ── binary watcher ──────────────────────────────────────────────────

// Append a line to the binwatch log with a human-readable timestamp and
// the supplied message. Best-effort — errors are swallowed.
static void binwatch_log(const char *msg) {
    int fd = open(VS_BINWATCH_LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tmv;
    localtime_r(&ts.tv_sec, &tmv);
    char line[512];
    int n = snprintf(line, sizeof(line),
                     "%04d-%02d-%02d %02d:%02d:%02d.%03ld %s\n",
                     tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
                     tmv.tm_hour, tmv.tm_min, tmv.tm_sec,
                     ts.tv_nsec / 1000000L, msg);
    if (n > 0) (void)!write(fd, line, (size_t)n);
    close(fd);
}

// stat() the binary path and return the mtime as a single ns counter.
// Returns 0 on failure.
static long binwatch_stat_mtime_ns(void) {
    struct stat st;
    if (stat(VS_BINWATCH_PATH, &st) != 0) return 0;
#ifdef __APPLE__
    return (long)st.st_mtimespec.tv_sec * 1000000000L + st.st_mtimespec.tv_nsec;
#else
    return (long)st.st_mtime * 1000000000L;
#endif
}

// Speculative prewarm hook — stub. A future implementation would spawn
// a shadow void_term with --prewarm so the next client attach is hot.
// That needs client-side cooperation (a --prewarm flag that parks the
// app without opening a window) which isn't in scope yet.
// TODO: spawn "/Applications/VOID.app/Contents/MacOS/void_term --prewarm"
// via posix_spawn + setsid so it outlives us.
static void prewarm_shadow_void_term(void) {
    binwatch_log("[prewarm] triggered (stub — no-op until client cooperation)");
}

// (Re)open the watched binary and register the vnode filter. Safe to
// call multiple times; existing fd/kq are reused when possible.
static int binwatch_register_filter(void) {
    if (g_binwatch_kq < 0 || g_binwatch_fd < 0) return -1;
    struct kevent kev;
    EV_SET(&kev, g_binwatch_fd, EVFILT_VNODE,
           EV_ADD | EV_ENABLE | EV_CLEAR,
           NOTE_WRITE | NOTE_ATTRIB | NOTE_DELETE | NOTE_RENAME,
           0, NULL);
    if (kevent(g_binwatch_kq, &kev, 1, NULL, 0, NULL) < 0) return -1;
    return 0;
}

// Open the binary path with O_EVTONLY and create the kqueue. Called once
// from main() after bind_listener(). On failure, sets the polling flag
// so the loop can fall back to stat() comparisons.
static void binwatch_init(void) {
    g_binary_mtime_ns = binwatch_stat_mtime_ns();

    g_binwatch_fd = open(VS_BINWATCH_PATH, O_EVTONLY);
    if (g_binwatch_fd < 0) {
        binwatch_log("[init] open(O_EVTONLY) failed — using stat() poll fallback");
        g_binwatch_poll_fallback = 1;
        return;
    }
    g_binwatch_kq = kqueue();
    if (g_binwatch_kq < 0) {
        close(g_binwatch_fd);
        g_binwatch_fd = -1;
        binwatch_log("[init] kqueue() failed — using stat() poll fallback");
        g_binwatch_poll_fallback = 1;
        return;
    }
    if (binwatch_register_filter() < 0) {
        close(g_binwatch_fd);
        close(g_binwatch_kq);
        g_binwatch_fd = -1;
        g_binwatch_kq = -1;
        binwatch_log("[init] EVFILT_VNODE register failed — using stat() poll fallback");
        g_binwatch_poll_fallback = 1;
        return;
    }
    binwatch_log("[init] kqueue watcher armed on " VS_BINWATCH_PATH);
}

// If the previous fd was invalidated (rename/delete/atomic replace),
// close it and re-open the path so subsequent events still fire. Returns
// 0 on success, -1 if the binary is currently missing.
static int binwatch_reopen(void) {
    if (g_binwatch_fd >= 0) {
        close(g_binwatch_fd);
        g_binwatch_fd = -1;
    }
    g_binwatch_fd = open(VS_BINWATCH_PATH, O_EVTONLY);
    if (g_binwatch_fd < 0) return -1;
    if (binwatch_register_filter() < 0) {
        close(g_binwatch_fd);
        g_binwatch_fd = -1;
        return -1;
    }
    return 0;
}

// Pump any pending kqueue events with a zero timeout. Called after each
// select() tick. Logs the fired flags and updates g_binary_mtime_ns. If
// the vnode was deleted or renamed, reopens the path so the filter keeps
// firing on the replacement inode.
static void binwatch_pump(void) {
    if (g_binwatch_poll_fallback) {
        long cur = binwatch_stat_mtime_ns();
        if (cur > 0 && cur != g_binary_mtime_ns) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "[poll] mtime changed %ld -> %ld (stat fallback)",
                     g_binary_mtime_ns, cur);
            binwatch_log(msg);
            g_binary_mtime_ns = cur;
            prewarm_shadow_void_term();
        }
        return;
    }
    if (g_binwatch_kq < 0) return;

    struct kevent events[4];
    struct timespec zero = {0, 0};
    int n = kevent(g_binwatch_kq, NULL, 0, events, 4, &zero);
    if (n <= 0) return;

    for (int i = 0; i < n; i++) {
        unsigned int f = events[i].fflags;
        char flagstr[128];
        int pos = 0;
        flagstr[0] = 0;
        if (f & NOTE_WRITE)  pos += snprintf(flagstr + pos, sizeof(flagstr) - pos, "%sNOTE_WRITE",  pos ? "|" : "");
        if (f & NOTE_ATTRIB) pos += snprintf(flagstr + pos, sizeof(flagstr) - pos, "%sNOTE_ATTRIB", pos ? "|" : "");
        if (f & NOTE_DELETE) pos += snprintf(flagstr + pos, sizeof(flagstr) - pos, "%sNOTE_DELETE", pos ? "|" : "");
        if (f & NOTE_RENAME) pos += snprintf(flagstr + pos, sizeof(flagstr) - pos, "%sNOTE_RENAME", pos ? "|" : "");
        if (!pos) snprintf(flagstr, sizeof(flagstr), "0x%x", f);

        long new_mtime = binwatch_stat_mtime_ns();
        char msg[384];
        snprintf(msg, sizeof(msg),
                 "[event] fflags=%s mtime=%ld (prev=%ld)",
                 flagstr, new_mtime, g_binary_mtime_ns);
        binwatch_log(msg);
        if (new_mtime > 0) g_binary_mtime_ns = new_mtime;

        if (f & NOTE_WRITE) {
            prewarm_shadow_void_term();
        }
        if (f & (NOTE_DELETE | NOTE_RENAME)) {
            // Atomic replace (mv new old) invalidates our fd — reopen
            // so the next build still fires events.
            if (binwatch_reopen() == 0) {
                binwatch_log("[event] reopened binary after DELETE/RENAME");
                long m2 = binwatch_stat_mtime_ns();
                if (m2 > 0) g_binary_mtime_ns = m2;
            } else {
                binwatch_log("[event] reopen failed — binary path missing");
            }
        }
    }
}

// ── Merkle delta sync (section hashes) ──────────────────────────────

// Number of sections covering the live rows of this session. 64 lines
// per section, plus one trailing section for any remainder.
#define VS_N_SECTIONS  ((VS_GRID_ROWS + VS_SECTION_LINES - 1) / VS_SECTION_LINES)

// Recompute the per-section Merkle hash for every section flagged
// dirty. Called from pump_sessions after each drain and at the top of
// handle_attach so the reply never ships stale hashes. Rows past
// VS_GRID_ROWS are zero-padded so client and server see the same byte
// sequence regardless of session resize.
static void update_session_hashes(VsSession *s) {
    if (!s || !s->used) return;
    int cols = s->cols > 0 ? s->cols : VS_GRID_COLS;
    if (cols > VS_GRID_COLS) cols = VS_GRID_COLS;
    size_t per_row = (size_t)cols * sizeof(VsCell);
    unsigned char zeros[VS_GRID_COLS * sizeof(VsCell)];
    memset(zeros, 0, per_row);
    for (int sec = 0; sec < VS_N_SECTIONS; sec++) {
        if (!s->section_dirty[sec]) continue;
        int row0 = sec * VS_SECTION_LINES;
        uint64_t h = 0xcbf29ce484222325ULL;
        for (int dr = 0; dr < VS_SECTION_LINES; dr++) {
            int r = row0 + dr;
            const unsigned char *p = (r >= VS_GRID_ROWS)
                ? zeros
                : (const unsigned char *)&s->grid[r * VS_GRID_COLS];
            for (size_t i = 0; i < per_row; i++) {
                h ^= p[i];
                h *= 0x100000001b3ULL;
            }
        }
        s->section_hash[sec] = h;
        s->section_dirty[sec] = 0;
    }
}

// ── semantic labeling ────────────────────────────────────────────────

// Derive a readable label from cwd + dominant child process.
//   "/Users/ghost/Dev/nexus" + "claude" → "nexus-claude"
//   "/Users/ghost/Dev/void"  + "zsh"    → "void"
// No embeddings in v1 — this is heuristic only.
static void derive_label(const char *cwd, const char *cmd,
                         pid_t shell_pid, char out[64]) {
    const char *tail = strrchr(cwd, '/');
    tail = tail ? tail + 1 : cwd;
    if (!*tail) tail = "home";

    // Best-effort dominant-process sniff. Scan all pids for direct children
    // of the shell pid and pick the first non-shell name.
    char proc[32] = {0};
    if (shell_pid > 0) {
        int pids[4096];
        int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
        int n = bytes / (int)sizeof(int);
        for (int i = 0; i < n; i++) {
            pid_t p = pids[i];
            if (p <= 0) continue;
            struct proc_bsdinfo info;
            if (proc_pidinfo(p, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) <= 0)
                continue;
            if ((pid_t)info.pbi_ppid != shell_pid) continue;
            const char *nm = info.pbi_comm;
            if (!*nm) continue;
            if (!strcmp(nm, "zsh") || !strcmp(nm, "bash") || !strcmp(nm, "sh") ||
                !strcmp(nm, "fish") || !strcmp(nm, "dash")) continue;
            snprintf(proc, sizeof(proc), "%s", nm);
            break;
        }
    }

    if (proc[0])
        snprintf(out, 64, "%s-%s", tail, proc);
    else
        snprintf(out, 64, "%s", tail);
    // Strip non-label chars
    for (char *q = out; *q; q++) {
        if (*q == ' ' || *q == '/' || *q == '\\') *q = '-';
    }
}

// ── process classifier ───────────────────────────────────────────────

typedef enum {
    STRAT_DEFAULT    = 0, // hold PTY open, session persists
    STRAT_CHECKPOINT = 1, // claude et al — snapshot on detach, resume later
    STRAT_PROTECT    = 2, // vim/less/nano — warn before close (has buffer)
    STRAT_TRANSIENT  = 3, // shell only — OK to garbage-collect after N hours idle
} VsStrategy;

static VsStrategy classify_process(const char *name) {
    if (!name || !*name) return STRAT_DEFAULT;
    if (!strcmp(name, "claude"))   return STRAT_CHECKPOINT;
    if (!strcmp(name, "cl"))       return STRAT_CHECKPOINT;
    if (!strcmp(name, "vim"))      return STRAT_PROTECT;
    if (!strcmp(name, "nvim"))     return STRAT_PROTECT;
    if (!strcmp(name, "nano"))     return STRAT_PROTECT;
    if (!strcmp(name, "emacs"))    return STRAT_PROTECT;
    if (!strcmp(name, "less"))     return STRAT_PROTECT;
    if (!strcmp(name, "fswatch"))  return STRAT_DEFAULT;
    if (!strcmp(name, "node"))     return STRAT_DEFAULT;
    if (!strcmp(name, "python"))   return STRAT_DEFAULT;
    if (!strcmp(name, "zsh"))      return STRAT_TRANSIENT;
    if (!strcmp(name, "bash"))     return STRAT_TRANSIENT;
    if (!strcmp(name, "sh"))       return STRAT_TRANSIENT;
    return STRAT_DEFAULT;
}

// Enumerate descendants of `root_pid`, fill `out` with comma-separated names
// like "zsh(2), claude, fswatch". Returns total process count (excluding root).
static int enumerate_descendants(pid_t root_pid, char *out, size_t outsz) {
    int pids[4096];
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    if (bytes <= 0) return 0;
    int n = bytes / (int)sizeof(int);

    struct { char name[32]; int count; } bucket[32];
    int bn = 0;
    int total = 0;

    for (int i = 0; i < n; i++) {
        pid_t p = pids[i];
        if (p <= 0 || p == root_pid) continue;
        // Walk ancestors up to depth 16
        pid_t a = p;
        int depth = 0;
        int match = 0;
        while (a > 1 && depth < 16) {
            struct proc_bsdinfo info;
            if (proc_pidinfo(a, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) <= 0)
                break;
            a = (pid_t)info.pbi_ppid;
            if (a == root_pid) { match = 1; break; }
            depth++;
        }
        if (!match) continue;
        char name[32] = {0};
        proc_name(p, name, sizeof(name));
        if (!name[0]) continue;
        total++;
        int found = -1;
        for (int k = 0; k < bn; k++)
            if (!strcmp(bucket[k].name, name)) { found = k; break; }
        if (found >= 0) {
            bucket[found].count++;
        } else if (bn < 32) {
            snprintf(bucket[bn].name, sizeof(bucket[bn].name), "%s", name);
            bucket[bn].count = 1;
            bn++;
        }
    }

    size_t pos = 0;
    for (int k = 0; k < bn; k++) {
        if (pos >= outsz - 1) break;
        int w;
        if (bucket[k].count > 1)
            w = snprintf(out + pos, outsz - pos, "%s%s(%d)",
                         pos ? ", " : "", bucket[k].name, bucket[k].count);
        else
            w = snprintf(out + pos, outsz - pos, "%s%s",
                         pos ? ", " : "", bucket[k].name);
        if (w < 0) break;
        pos += (size_t)w;
    }
    out[outsz - 1] = 0;
    return total;
}

// ── session management ──────────────────────────────────────────────

static VsSession *find_session(const char *id) {
    for (int i = 0; i < VS_MAX_SESSIONS; i++) {
        if (g_sessions[i].used && !strcmp(g_sessions[i].id, id))
            return &g_sessions[i];
    }
    return NULL;
}

static VsSession *alloc_session(void) {
    for (int i = 0; i < VS_MAX_SESSIONS; i++) {
        if (!g_sessions[i].used) {
            memset(&g_sessions[i], 0, sizeof(VsSession));
            g_sessions[i].used = 1;
            g_sessions[i].pty_fd = -1;
            g_sessions[i].attached_client_fd = -1;
            return &g_sessions[i];
        }
    }
    return NULL;
}

static void free_session(VsSession *s) {
    if (!s) return;
    if (s->pty_fd >= 0) close(s->pty_fd);
    if (s->shell_pid > 0) {
        kill(-s->shell_pid, SIGTERM);
        waitpid(s->shell_pid, NULL, WNOHANG);
    }
    memset(s, 0, sizeof(VsSession));
    s->pty_fd = -1;
    s->attached_client_fd = -1;
}

// Fork a shell + PTY, store in session. Returns 0 on success.
static int spawn_session_pty(VsSession *s,
                             const char *cwd, const char *cmd,
                             int rows, int cols) {
    struct winsize ws;
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) return -1;

    if (pid == 0) {
        // Child — exec the shell
        setenv("TERM", "xterm-256color", 1);
        setenv("LANG", "en_US.UTF-8", 1);
        // Give the child a fresh user-writable PATH so profile commands
        // work under Finder/LaunchServices sparse envs.
        const char *old = getenv("PATH") ?: "/usr/bin:/bin";
        char np[2048];
        snprintf(np, sizeof(np),
                 "%s/.local/bin:%s/bin:/opt/homebrew/bin:/usr/local/bin:%s",
                 getenv("HOME") ?: "", getenv("HOME") ?: "", old);
        setenv("PATH", np, 1);
        // New session so orphaned shells survive any accidental ppid check
        setsid();

        const char *sh = getenv("SHELL");
        if (!sh) sh = "/bin/zsh";

        if (cwd && *cwd) chdir(cwd);

        if (cmd && *cmd) {
            char script[1200];
            snprintf(script, sizeof(script), "%s; exec %s -l", cmd, sh);
            execl(sh, sh, "-l", "-c", script, (char *)NULL);
        } else {
            execl(sh, sh, "-l", (char *)NULL);
        }
        _exit(127);
    }

    int fl = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, fl | O_NONBLOCK);
    // VS-17: set FD_CLOEXEC on the PTY master so the next spawn's
    // forkpty doesn't leak this session's master into the other
    // shell's address space. Single-process model means we no longer
    // get automatic fd isolation from a fork boundary.
    int mfl = fcntl(master, F_GETFD);
    if (mfl >= 0) fcntl(master, F_SETFD, mfl | FD_CLOEXEC);
    s->pty_fd = master;
    s->shell_pid = pid;
    s->rows = rows;
    s->cols = cols;
    snprintf(s->cwd, sizeof(s->cwd), "%s", cwd ? cwd : "");
    snprintf(s->cmd_launched, sizeof(s->cmd_launched), "%s", cmd ? cmd : "");
    derive_label(s->cwd, cmd, pid, s->label);
    s->last_activity_ns = now_ns();

    // Fill grid with spaces
    for (int i = 0; i < VS_GRID_ROWS * VS_GRID_COLS; i++) {
        s->grid[i].ch    = ' ';
        s->grid[i].fg    = 7;
        s->grid[i].bg    = 0;
        s->grid[i].flags = 0;
    }
    // Mark every section dirty so the first ATTACH computes real hashes
    // from the space-fill grid instead of returning the zero-init values.
    for (int sec = 0; sec < VS_N_SECTIONS; sec++)
        s->section_dirty[sec] = 1;
    return 0;
}

// ── VS-06: reanimate tombstone ──────────────────────────────────────
//
// Re-spawn a shell for a checkpoint-restored (tombstone) session so it
// becomes a live session again. Preserves the existing grid+cursor so
// the client can see the last frame immediately; the new shell repaints
// over it on its first prompt.
static int reanimate_session(VsSession *s) {
    if (!s || !s->used) return -1;
    if (s->pty_fd >= 0) return 0; // already alive
    if (spawn_session_pty(s, s->cwd, s->cmd_launched,
                          s->rows > 0 ? s->rows : 24,
                          s->cols > 0 ? s->cols : 80) != 0)
        return -1;
    s->is_checkpoint_restored = 0;
    // Don't clear the grid — keep the last checkpoint frame so the
    // ATTACH response includes readable content until the new shell
    // paints its first prompt. The section hashes are already marked
    // dirty from scan_and_restore_checkpoints, so the next ATTACH
    // will compute fresh hashes.
    return 0;
}

// ── checkpointing ───────────────────────────────────────────────────

typedef struct {
    uint32_t magic;          // 'VCKP'
    char     id[32];
    char     label[64];
    char     cwd[512];
    char     cmd_launched[512];
    int32_t  rows, cols;
    int32_t  cur_row, cur_col;
    // grid follows
} VsCkptHeader;
#define VS_CKPT_MAGIC 0x564B5056u // 'VCKP'? layout matches FourCC

static void ensure_ckpt_dir(void) {
    mkdir(VS_CKPT_DIR, 0755);
}

static void checkpoint_session(const VsSession *s) {
    ensure_ckpt_dir();
    char path[512];
    snprintf(path, sizeof(path), "%s/%s.bin", VS_CKPT_DIR, s->id);
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    VsCkptHeader h = {0};
    h.magic = VS_CKPT_MAGIC;
    memcpy(h.id, s->id, sizeof(h.id));
    memcpy(h.label, s->label, sizeof(h.label));
    memcpy(h.cwd, s->cwd, sizeof(h.cwd));
    memcpy(h.cmd_launched, s->cmd_launched, sizeof(h.cmd_launched));
    h.rows = s->rows;
    h.cols = s->cols;
    h.cur_row = s->cur_row;
    h.cur_col = s->cur_col;
    write(fd, &h, sizeof(h));
    write(fd, s->grid, sizeof(s->grid));
    close(fd);
}

// VS-03 fix: keep the newest `max_keep` checkpoint files, unlink the rest.
// Called from main() before scan_and_restore_checkpoints() so the restored
// session table never overflows g_sessions[VS_MAX_SESSIONS].
static void prune_old_checkpoints(int max_keep) {
    DIR *d = opendir(VS_CKPT_DIR);
    if (!d) return;
    typedef struct { char name[256]; time_t mtime; } CkptEnt;
    CkptEnt *ents = NULL;
    int n = 0, cap = 0;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        char path[1024];
        snprintf(path, sizeof(path), "%s/%s", VS_CKPT_DIR, ent->d_name);
        struct stat st;
        if (stat(path, &st) != 0) continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 32;
            CkptEnt *ne = (CkptEnt *)realloc(ents, cap * sizeof(CkptEnt));
            if (!ne) { free(ents); closedir(d); return; }
            ents = ne;
        }
        snprintf(ents[n].name, sizeof(ents[n].name), "%s", ent->d_name);
        ents[n].mtime = st.st_mtime;
        n++;
    }
    closedir(d);
    if (n <= max_keep) { free(ents); return; }
    // Simple insertion sort by mtime descending (newest first)
    for (int i = 1; i < n; i++) {
        CkptEnt k = ents[i];
        int j = i - 1;
        while (j >= 0 && ents[j].mtime < k.mtime) {
            ents[j + 1] = ents[j];
            j--;
        }
        ents[j + 1] = k;
    }
    int pruned = 0;
    for (int i = max_keep; i < n; i++) {
        char path[1024];
        snprintf(path, sizeof(path), "%s/%s", VS_CKPT_DIR, ents[i].name);
        if (unlink(path) == 0) pruned++;
    }
    free(ents);
    if (pruned > 0)
        fprintf(stderr, "void_server: pruned %d old checkpoint(s), kept %d\n",
                pruned, max_keep);
}

static void scan_and_restore_checkpoints(void) {
    // On startup, load any ckpt files as "restored" sessions without a
    // live PTY. These show up in LIST and clients can see the last frame,
    // but attaching won't resume a shell — they're tombstones of crashed
    // sessions. A future version could re-spawn + replay stdin to rebuild.
    DIR *d = opendir(VS_CKPT_DIR);
    if (!d) return;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        char path[1024];
        snprintf(path, sizeof(path), "%s/%s", VS_CKPT_DIR, ent->d_name);
        int fd = open(path, O_RDONLY);
        if (fd < 0) continue;
        VsCkptHeader h;
        if (read(fd, &h, sizeof(h)) != (ssize_t)sizeof(h) ||
            h.magic != VS_CKPT_MAGIC) {
            close(fd);
            continue;
        }
        VsSession *s = alloc_session();
        if (!s) { close(fd); break; }
        memcpy(s->id, h.id, sizeof(s->id));
        memcpy(s->label, h.label, sizeof(s->label));
        memcpy(s->cwd, h.cwd, sizeof(s->cwd));
        memcpy(s->cmd_launched, h.cmd_launched, sizeof(s->cmd_launched));
        s->rows = h.rows;
        s->cols = h.cols;
        s->cur_row = h.cur_row;
        s->cur_col = h.cur_col;
        read(fd, s->grid, sizeof(s->grid));
        s->is_checkpoint_restored = 1;
        s->pty_fd = -1;
        // Force a rehash on first ATTACH — we don't trust any hash
        // we might have written into the checkpoint.
        for (int sec = 0; sec < VS_N_SECTIONS; sec++)
            s->section_dirty[sec] = 1;
        close(fd);
    }
    closedir(d);
}

// ── unix socket I/O ─────────────────────────────────────────────────

static int read_exact(int fd, void *buf, size_t n) {
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, (char *)buf + got, n - got);
        if (r == 0) return -1;
        if (r < 0) { if (errno == EINTR) continue; return -1; }
        got += (size_t)r;
    }
    return 0;
}

static int write_exact(int fd, const void *buf, size_t n) {
    size_t sent = 0;
    while (sent < n) {
        ssize_t w = write(fd, (const char *)buf + sent, n - sent);
        if (w <= 0) { if (errno == EINTR) continue; return -1; }
        sent += (size_t)w;
    }
    return 0;
}

// Send a response header + optional fd via SCM_RIGHTS.
static int send_response(int client_fd, uint32_t status,
                         const void *body, size_t body_len,
                         int fd_to_pass) {
    uint32_t hdr[3];
    hdr[0] = VS_MAGIC;
    hdr[1] = status;
    hdr[2] = (uint32_t)body_len;

    struct msghdr msg = {0};
    struct iovec iov[2];
    iov[0].iov_base = hdr;
    iov[0].iov_len  = sizeof(hdr);
    int iovn = 1;
    if (body_len > 0) {
        iov[1].iov_base = (void *)body;
        iov[1].iov_len  = body_len;
        iovn = 2;
    }
    msg.msg_iov = iov;
    msg.msg_iovlen = iovn;

    char ctrl[CMSG_SPACE(sizeof(int))];
    if (fd_to_pass >= 0) {
        memset(ctrl, 0, sizeof(ctrl));
        msg.msg_control = ctrl;
        msg.msg_controllen = sizeof(ctrl);
        struct cmsghdr *cm = CMSG_FIRSTHDR(&msg);
        cm->cmsg_level = SOL_SOCKET;
        cm->cmsg_type  = SCM_RIGHTS;
        cm->cmsg_len   = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(cm), &fd_to_pass, sizeof(int));
    }

    ssize_t r = sendmsg(client_fd, &msg, 0);
    return r > 0 ? 0 : -1;
}

// ── command handlers ────────────────────────────────────────────────

static int handle_spawn(int client_fd, const char *body, uint32_t len) {
    if (len < 64 + 512 + 512 + 4) return -1;
    const char *title = body;
    const char *cwd   = body + 64;
    const char *cmd   = body + 64 + 512;
    uint16_t rows, cols;
    memcpy(&rows, body + 64 + 512 + 512, 2);
    memcpy(&cols, body + 64 + 512 + 512 + 2, 2);

    VsSession *s = alloc_session();
    if (!s) {
        send_response(client_fd, 1, NULL, 0, -1);
        return 0;
    }
    gen_session_id(s->id);
    snprintf(s->label, sizeof(s->label), "%s", title[0] ? title : "session");

    if (spawn_session_pty(s, cwd, cmd, rows, cols) != 0) {
        free_session(s);
        send_response(client_fd, 2, NULL, 0, -1);
        return 0;
    }
    // override label with derived version
    if (title[0])
        snprintf(s->label, sizeof(s->label), "%s", title);
    else
        derive_label(s->cwd, cmd, s->shell_pid, s->label);

    s->attached_client_fd = client_fd;
    s->last_attach_mtime = (uint64_t)g_binary_mtime_ns;

    // Response: session_id
    char resp[32 + 4] = {0};
    memcpy(resp, s->id, 32);
    uint32_t hint = (uint32_t)s->pty_fd;
    memcpy(resp + 32, &hint, 4);

    send_response(client_fd, 0, resp, sizeof(resp), s->pty_fd);
    return 0;
}

// Build a Merkle-delta ATTACH response body. Returns a malloc'd buffer
// (caller frees) and writes the total length into *out_len. Compares
// each server section hash against the corresponding entry in
// client_hashes[] (or treats it as zero/mismatch if k >= n_client_hashes
// so the client gets the full payload on first attach).
//
// Layout:
//   uint16 rows
//   uint16 cols
//   uint32 n_sections
//   repeat n_sections:
//     uint32 section_idx
//     uint32 section_bytes  (0 when hash matches, else SECTION_LINES * cols * sizeof(VsCell))
//     uint64 server_hash
//     bytes  payload        (present iff section_bytes > 0)
static char *build_attach_body(VsSession *s,
                               const uint64_t *client_hashes,
                               uint32_t n_client_hashes,
                               size_t *out_len) {
    // Ensure hashes are current — pump_sessions usually did this already
    // but a second call is cheap (section_dirty gate) and guarantees we
    // never emit stale entries.
    update_session_hashes(s);

    int cols = s->cols > 0 ? s->cols : VS_GRID_COLS;
    if (cols > VS_GRID_COLS) cols = VS_GRID_COLS;
    uint32_t n_sections = VS_N_SECTIONS;
    size_t section_payload = (size_t)VS_SECTION_LINES * (size_t)cols * sizeof(VsCell);

    // Worst case: every section dirty → header + n_sections * (16 + payload)
    size_t worst =
        2 + 2 + 4 +
        (size_t)n_sections * (4 + 4 + 8 + section_payload);
    char *buf = (char *)malloc(worst);
    if (!buf) { *out_len = 0; return NULL; }
    size_t off = 0;

    uint16_t rows16 = (uint16_t)s->rows;
    uint16_t cols16 = (uint16_t)s->cols;
    memcpy(buf + off, &rows16, 2); off += 2;
    memcpy(buf + off, &cols16, 2); off += 2;
    memcpy(buf + off, &n_sections, 4); off += 4;

    for (uint32_t k = 0; k < n_sections; k++) {
        uint64_t server_hash = s->section_hash[k];
        // Fall back to a guaranteed-mismatch sentinel (0) when the client
        // didn't send a hash for this section — a first-attach client
        // passes n=0 and gets the full grid this way.
        uint64_t client_hash = (k < n_client_hashes) ? client_hashes[k] : 0;
        int matches = (k < n_client_hashes) && (client_hash == server_hash);

        uint32_t idx32 = k;
        uint32_t bytes32 = matches ? 0u : (uint32_t)section_payload;
        memcpy(buf + off, &idx32, 4);       off += 4;
        memcpy(buf + off, &bytes32, 4);     off += 4;
        memcpy(buf + off, &server_hash, 8); off += 8;
        if (!matches) {
            // Copy SECTION_LINES rows worth of live cells (first `cols`
            // columns each). Rows past s->rows are still zeroed from the
            // initial clear, which hashes consistently on both sides.
            int row0 = (int)k * VS_SECTION_LINES;
            for (int dr = 0; dr < VS_SECTION_LINES; dr++) {
                int r = row0 + dr;
                if (r >= VS_GRID_ROWS) {
                    memset(buf + off, 0, (size_t)cols * sizeof(VsCell));
                } else {
                    memcpy(buf + off,
                           &s->grid[r * VS_GRID_COLS],
                           (size_t)cols * sizeof(VsCell));
                }
                off += (size_t)cols * sizeof(VsCell);
            }
        }
    }
    *out_len = off;
    return buf;
}

static int handle_attach(int client_fd, const char *body, uint32_t len) {
    // New body layout: id[32] + uint32 n + uint64[n]. The classic
    // 32-byte-only request is accepted as n=0 for backwards compat.
    if (len < 32) return -1;
    char id[32] = {0};
    memcpy(id, body, 32);

    uint32_t n_client = 0;
    const uint64_t *client_hashes = NULL;
    if (len >= 32 + 4) {
        memcpy(&n_client, body + 32, 4);
        // Sanity — cap at VS_N_SECTIONS; extra entries are ignored.
        if (n_client > VS_N_SECTIONS) n_client = VS_N_SECTIONS;
        // Make sure the body is actually long enough to hold n hashes.
        if (len < 32 + 4 + (size_t)n_client * 8) {
            n_client = 0;
        } else if (n_client > 0) {
            client_hashes = (const uint64_t *)(body + 32 + 4);
        }
    }

    VsSession *s = find_session(id);
    if (!s) {
        send_response(client_fd, 1, NULL, 0, -1);
        return 0;
    }

    // Ensure hashes are live before we assemble the response so the
    // first post-spawn ATTACH sees the already-printed banner rows.
    update_session_hashes(s);

    if (s->is_checkpoint_restored || s->pty_fd < 0) {
        // VS-06: try to reanimate the tombstone — spawn a fresh shell
        // with the original cwd/cmd, keeping the saved grid for the
        // attach response. If reanimate succeeds, fall through to the
        // normal live-attach path below.
        if (reanimate_session(s) != 0) {
            // Reanimate failed — return the frozen grid with status=3
            // so the client can at least see the last frame.
            size_t body_len = 0;
            char *resp = build_attach_body(s, client_hashes, n_client, &body_len);
            if (!resp) {
                send_response(client_fd, 2, NULL, 0, -1);
                return 0;
            }
            send_response(client_fd, 3, resp, body_len, -1);
            free(resp);
            return 0;
        }
    }

    s->attached_client_fd = client_fd;
    s->last_attach_mtime = (uint64_t)g_binary_mtime_ns;
    size_t body_len = 0;
    char *resp = build_attach_body(s, client_hashes, n_client, &body_len);
    if (!resp) {
        send_response(client_fd, 2, NULL, 0, -1);
        return 0;
    }
    send_response(client_fd, 0, resp, body_len, s->pty_fd);
    free(resp);
    return 0;
}

static int handle_detach(int client_fd, const char *body, uint32_t len) {
    if (len < 32) return -1;
    char id[32] = {0};
    memcpy(id, body, 32);
    VsSession *s = find_session(id);
    if (!s) {
        send_response(client_fd, 1, NULL, 0, -1);
        return 0;
    }
    if (s->attached_client_fd == client_fd)
        s->attached_client_fd = -1;
    // Write a checkpoint on detach so crash-resurrection has something to find
    checkpoint_session(s);
    send_response(client_fd, 0, NULL, 0, -1);
    return 0;
}

static int handle_list(int client_fd, const char *body, uint32_t len) {
    (void)body; (void)len;
    uint32_t n = 0;
    for (int i = 0; i < VS_MAX_SESSIONS; i++)
        if (g_sessions[i].used) n++;

    // Header area: current_binary_mtime (uint64) + n (uint32). Older
    // clients that only read the first 4 bytes as `n` will see a bogus
    // count, so we put the mtime FIRST and leave n right after. A new
    // client decodes both; old clients need a recompile anyway because
    // of this layout change. Since void_term ships with the server in
    // the same build, this is always safe (hot-swap is atomic).
    size_t each = 32 + 64 + 256 + 4 + 32 * 32 + 8;
    size_t body_len = 8 + 4 + n * each;
    char *resp = (char *)calloc(1, body_len);
    char *p = resp;
    uint64_t cur_mtime = (uint64_t)g_binary_mtime_ns;
    memcpy(p, &cur_mtime, 8); p += 8;
    memcpy(p, &n, 4); p += 4;
    for (int i = 0; i < VS_MAX_SESSIONS; i++) {
        VsSession *s = &g_sessions[i];
        if (!s->used) continue;
        memcpy(p, s->id, 32); p += 32;
        memcpy(p, s->label, 64); p += 64;
        memcpy(p, s->cwd, 256); p += 256;
        char names[1024] = {0};
        int total = s->shell_pid > 0
            ? enumerate_descendants(s->shell_pid, names, sizeof(names))
            : 0;
        uint32_t pc = (uint32_t)total;
        memcpy(p, &pc, 4); p += 4;
        // Just stuff the names string into the first 32-byte slot for now;
        // a richer client can parse individual names but v1 UI only shows
        // the concatenated string.
        snprintf(p, 32 * 32, "%s", names);
        p += 32 * 32;
        // Per-session attach mtime — new clients diff against the
        // header's current_binary_mtime to know if a hot-swap happened
        // while this session was detached.
        uint64_t atm = s->last_attach_mtime;
        memcpy(p, &atm, 8); p += 8;
    }
    send_response(client_fd, 0, resp, body_len, -1);
    free(resp);
    return 0;
}

static int handle_kill(int client_fd, const char *body, uint32_t len) {
    if (len < 32) return -1;
    char id[32] = {0};
    memcpy(id, body, 32);
    VsSession *s = find_session(id);
    if (!s) {
        send_response(client_fd, 1, NULL, 0, -1);
        return 0;
    }
    free_session(s);
    // Remove ckpt file
    char path[512];
    snprintf(path, sizeof(path), "%s/%s.bin", VS_CKPT_DIR, id);
    unlink(path);
    send_response(client_fd, 0, NULL, 0, -1);
    return 0;
}

static int handle_ping(int client_fd, const char *body, uint32_t len) {
    (void)body; (void)len;
    const char *pong = "pong";
    send_response(client_fd, 0, pong, 4, -1);
    return 0;
}

// ── client dispatch (VS-17 non-blocking single process) ────────────
//
// Each accepted client is non-blocking. Bytes arrive in any chunks; we
// buffer into g_clients[idx].recv_buf and try to parse complete request
// frames (hdr[3] + body[hdr[2]]) off the front. Each complete frame is
// dispatched to the existing command handlers, which already use
// blocking sendmsg on the client fd; that's fine in practice because
// the kernel's socket send buffer is orders of magnitude larger than
// any response (the biggest, an ATTACH full-grid reply, is ~400 KB and
// SO_SNDBUF for AF_UNIX is at least 1 MB on macOS). send_response
// returning -1 just means the peer died; we drop the client on the
// next loop tick.

// Try to parse as many complete frames off the head of the client's
// recv_buf as possible and dispatch each one. Returns 0 to keep the
// client alive, -1 to drop it (bad magic, oversized frame, or a
// handler that explicitly requested disconnection).
static int client_try_dispatch(int idx) {
    VsClient *cl = &g_clients[idx];
    for (;;) {
        if (cl->recv_have < sizeof(uint32_t) * 3) return 0; // need header
        uint32_t hdr[3];
        memcpy(hdr, cl->recv_buf, sizeof(hdr));
        if (hdr[0] != VS_MAGIC) return -1;
        uint32_t cmd  = hdr[1];
        uint32_t blen = hdr[2];
        if (blen > VS_CLIENT_RECV_BUF_SIZE - sizeof(hdr)) return -1; // sanity
        size_t total = sizeof(hdr) + blen;
        if (cl->recv_have < total) return 0; // body still arriving

        const char *body = (const char *)(cl->recv_buf + sizeof(hdr));
        int rc = 0;
        int fd = cl->fd;
        switch (cmd) {
            case VS_SPAWN:  rc = handle_spawn (fd, body, blen); break;
            case VS_ATTACH: rc = handle_attach(fd, body, blen); break;
            case VS_DETACH: rc = handle_detach(fd, body, blen); break;
            case VS_LIST:   rc = handle_list  (fd, body, blen); break;
            case VS_KILL:   rc = handle_kill  (fd, body, blen); break;
            case VS_PING:   rc = handle_ping  (fd, body, blen); break;
            default: send_response(fd, 99, NULL, 0, -1); break;
        }

        // Consume this frame from the buffer
        size_t remain = cl->recv_have - total;
        if (remain > 0) {
            memmove(cl->recv_buf, cl->recv_buf + total, remain);
        }
        cl->recv_have = remain;

        if (rc < 0) return -1;
    }
}

// Drain readable bytes from the client socket into its recv buffer and
// dispatch any complete frames. Returns 0 if the client is still alive,
// -1 if we should drop it (EOF, fatal error, or bad frame).
static int client_on_readable(int idx) {
    VsClient *cl = &g_clients[idx];
    for (;;) {
        size_t cap = VS_CLIENT_RECV_BUF_SIZE - cl->recv_have;
        if (cap == 0) {
            // Buffer full without a complete frame — something is very
            // wrong. Drop the client.
            return -1;
        }
        ssize_t r = read(cl->fd, cl->recv_buf + cl->recv_have, cap);
        if (r > 0) {
            cl->recv_have += (size_t)r;
            continue;
        }
        if (r == 0) return -1; // EOF
        if (r < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            return -1;
        }
    }
    return client_try_dispatch(idx);
}

// Close the client, mark any sessions it owned as detached but alive,
// checkpoint them so crash-resurrection has something to find. The
// PTY master fds are kept open by the listener, so the spawned
// processes keep running — this is the whole point of VS-17.
static void client_on_disconnect(int idx) {
    if (idx < 0 || idx >= VS_MAX_CLIENTS) return;
    VsClient *cl = &g_clients[idx];
    if (!cl->used) return;
    int fd = cl->fd;
    for (int i = 0; i < VS_MAX_SESSIONS; i++) {
        if (g_sessions[i].used && g_sessions[i].attached_client_fd == fd) {
            g_sessions[i].attached_client_fd = -1;
            checkpoint_session(&g_sessions[i]);
        }
    }
    if (fd >= 0) close(fd);
    free_client_slot(idx);
}

// ── PTY pumping (VS-17 per-session, event-driven) ──────────────────
//
// Drain one session's PTY master into its grid as best-effort plain
// text. Called from the main select loop whenever the PTY master fd
// reports readable. The bytes go into s->grid for LIST/checkpoint
// preview; the attached client sees them directly via the PTY master
// fd we passed it via SCM_RIGHTS. If read returns 0 the shell has
// exited — we close the master, checkpoint, and leave the session as
// a tombstone in g_sessions so LIST still reports it.
static void pump_one_session(int session_idx) {
    VsSession *s = &g_sessions[session_idx];
    if (!s->used || s->pty_fd < 0) return;

    int wrote_any = 0;
    int shell_gone = 0;
    char buf[VS_READ_BUF_SIZE];
    for (;;) {
        ssize_t n = read(s->pty_fd, buf, sizeof(buf));
        if (n > 0) {
            wrote_any = 1;
            s->last_activity_ns = now_ns();
            // Naive plain-text grid update for background preview only —
            // strips ESC sequences by skipping bytes between ESC and the
            // next final byte. Real VT parsing happens on the client side.
            for (ssize_t k = 0; k < n; k++) {
                unsigned char c = (unsigned char)buf[k];
                if (c == 0x1b) {
                    // Skip until a byte in 0x40..0x7E
                    k++;
                    if (k < n && buf[k] == '[') k++;
                    while (k < n && !(buf[k] >= 0x40 && buf[k] <= 0x7E)) k++;
                    continue;
                }
                if (c == '\r') { s->cur_col = 0; continue; }
                if (c == '\n') {
                    s->cur_row++;
                    if (s->cur_row >= s->rows) {
                        // scroll
                        size_t row_bytes = sizeof(VsCell) * s->cols;
                        memmove(s->grid, s->grid + s->cols, row_bytes * (s->rows - 1));
                        VsCell *last = &s->grid[(s->rows - 1) * s->cols];
                        for (int c2 = 0; c2 < s->cols; c2++) {
                            last[c2].ch = ' '; last[c2].fg = 7; last[c2].bg = 0; last[c2].flags = 0;
                        }
                        s->cur_row = s->rows - 1;
                    }
                    continue;
                }
                if (c == '\b') { if (s->cur_col > 0) s->cur_col--; continue; }
                if (c < 0x20) continue;
                if (s->cur_row >= 0 && s->cur_row < s->rows &&
                    s->cur_col >= 0 && s->cur_col < s->cols) {
                    int idx = s->cur_row * s->cols + s->cur_col;
                    s->grid[idx].ch = c;
                    s->grid[idx].fg = 7;
                    s->grid[idx].bg = 0;
                    s->grid[idx].flags = 0;
                }
                s->cur_col++;
                if (s->cur_col >= s->cols) {
                    s->cur_col = 0;
                    s->cur_row++;
                }
            }
            for (int sec = 0; sec < VS_N_SECTIONS; sec++)
                s->section_dirty[sec] = 1;
            continue;
        }
        if (n == 0) {
            // EOF — the shell closed the slave, which typically means
            // it exited. Mark for teardown below.
            shell_gone = 1;
            break;
        }
        // n < 0
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) break;
        // Any other read error — treat as shell gone.
        shell_gone = 1;
        break;
    }
    // Rehash dirty sections once per pump tick rather than per read.
    if (wrote_any) update_session_hashes(s);

    // Reap if child died (best-effort). Either the waitpid or the EOF
    // indicates the shell has exited.
    int status;
    if (!shell_gone && s->shell_pid > 0 &&
        waitpid(s->shell_pid, &status, WNOHANG) == s->shell_pid) {
        shell_gone = 1;
    }
    if (shell_gone) {
        if (s->pty_fd >= 0) close(s->pty_fd);
        s->pty_fd = -1;
        if (s->shell_pid > 0) {
            waitpid(s->shell_pid, NULL, WNOHANG);
            s->shell_pid = 0;
        }
        checkpoint_session(s);
    }
}

// ── signal handling + main loop ─────────────────────────────────────

static void sig_term_handler(int sig) { (void)sig; g_shutdown = 1; }

static int bind_listener(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) die("socket");
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", VS_SOCK_PATH);
    unlink(VS_SOCK_PATH);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) die("bind");
    listen(fd, 16);
    return fd;
}

// Double-fork daemonize — parent returns immediately, grandchild becomes
// the server process orphaned under launchd. Inherits stdin/out/err from
// the caller for debugging unless VOID_SERVER_QUIET is set.
static void daemonize_if_needed(void) {
    if (getenv("VOID_SERVER_FOREGROUND")) return;
    pid_t p = fork();
    if (p > 0) { _exit(0); }
    if (p < 0) die("fork daemon");
    setsid();
    pid_t p2 = fork();
    if (p2 > 0) { _exit(0); }
    if (p2 < 0) die("fork daemon2");
    // grandchild
    if (!getenv("VOID_SERVER_VERBOSE")) {
        int dn = open("/dev/null", O_RDWR);
        if (dn >= 0) { dup2(dn, 0); dup2(dn, 1); dup2(dn, 2); if (dn > 2) close(dn); }
    }
    chdir("/");
    umask(022);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;

    // If another server is already running, exit silently.
    {
        int t = socket(AF_UNIX, SOCK_STREAM, 0);
        if (t >= 0) {
            struct sockaddr_un addr = {0};
            addr.sun_family = AF_UNIX;
            snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", VS_SOCK_PATH);
            if (connect(t, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
                close(t);
                return 0;
            }
            close(t);
        }
    }

    daemonize_if_needed();
    signal(SIGTERM, sig_term_handler);
    signal(SIGINT,  sig_term_handler);
    signal(SIGPIPE, SIG_IGN);

    for (int i = 0; i < VS_MAX_SESSIONS; i++) {
        g_sessions[i].pty_fd = -1;
        g_sessions[i].attached_client_fd = -1;
    }
    for (int i = 0; i < VS_MAX_CLIENTS; i++) {
        g_clients[i].used = 0;
        g_clients[i].fd = -1;
    }
    // VS-03 fix: prune stale checkpoints before restoring, so the session
    // table cannot overflow from accumulated .bin files.
    prune_old_checkpoints(32);
    scan_and_restore_checkpoints();
    g_sock_listen = bind_listener();
    // Non-blocking accept so the select loop never stalls on a half-open
    // connection. VS-17 single-process architecture.
    set_nonblock(g_sock_listen);
    // VS-17 additional CLOEXEC: in the old fork-per-client model the
    // handler explicitly close()'d g_sock_listen after forking. Now
    // there is no fork boundary, so forkpty() inside spawn_session_pty
    // would leak the listen socket into every spawned shell. Set
    // FD_CLOEXEC so the listen socket disappears from the shell's fd
    // table automatically on execve().
    {
        int lfl = fcntl(g_sock_listen, F_GETFD);
        if (lfl >= 0) fcntl(g_sock_listen, F_SETFD, lfl | FD_CLOEXEC);
    }
    binwatch_init();
    // Same reasoning for the binwatch fds — they must never appear
    // in a spawned shell.
    if (g_binwatch_fd >= 0) {
        int bf = fcntl(g_binwatch_fd, F_GETFD);
        if (bf >= 0) fcntl(g_binwatch_fd, F_SETFD, bf | FD_CLOEXEC);
    }
    if (g_binwatch_kq >= 0) {
        int bk = fcntl(g_binwatch_kq, F_GETFD);
        if (bk >= 0) fcntl(g_binwatch_kq, F_SETFD, bk | FD_CLOEXEC);
    }

    // Unified select loop (VS-17):
    //   - Listener parent owns every PTY master. No fork-per-client.
    //   - Watches listen_sock + all client fds + all session PTY masters.
    //   - When a client dies, its slot is freed but the session's PTY
    //     stays open — the shell survives, which is the entire point.
    while (!g_shutdown) {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(g_sock_listen, &rfds);
        int maxfd = g_sock_listen;

        for (int i = 0; i < VS_MAX_CLIENTS; i++) {
            if (!g_clients[i].used) continue;
            int fd = g_clients[i].fd;
            if (fd < 0) continue;
            FD_SET(fd, &rfds);
            if (fd > maxfd) maxfd = fd;
        }
        for (int i = 0; i < VS_MAX_SESSIONS; i++) {
            if (!g_sessions[i].used) continue;
            int fd = g_sessions[i].pty_fd;
            if (fd < 0) continue;
            FD_SET(fd, &rfds);
            if (fd > maxfd) maxfd = fd;
        }

        // Reap any zombie shells that free_session couldn't catch
        // because the child hadn't fully exited yet. Without this we
        // accumulate <defunct> entries on every KILL. We're in a
        // single-process model now so there's nothing else to reap
        // them for us.
        for (;;) {
            int wst;
            pid_t p = waitpid(-1, &wst, WNOHANG);
            if (p <= 0) break;
        }

        // Short timeout so binwatch_pump runs periodically even without
        // socket activity and so any slow-path housekeeping we add later
        // still ticks.
        struct timeval tv = { 0, 50000 }; // 50 ms
        int r = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        // kqueue pump regardless of select outcome — binary watcher
        // fires whenever the bundle binary gets replaced.
        binwatch_pump();
        if (r < 0) { if (errno == EINTR) continue; break; }

        // Accept new connections. Non-blocking accept() — drain the
        // backlog in one go so multiple pending clients can come in
        // between ticks.
        if (FD_ISSET(g_sock_listen, &rfds)) {
            for (;;) {
                int c = accept(g_sock_listen, NULL, NULL);
                if (c < 0) {
                    if (errno == EINTR) continue;
                    break; // EAGAIN/EWOULDBLOCK or accept limit
                }
                // VS-02 fix: close-on-exec so spawned shells never inherit
                // the accepted client socket (prevents fd leak into zsh).
                int cfl = fcntl(c, F_GETFD);
                if (cfl >= 0) fcntl(c, F_SETFD, cfl | FD_CLOEXEC);
                set_nonblock(c);
                int idx = alloc_client_slot(c);
                if (idx < 0) {
                    // No free slot — politely refuse with status=99.
                    send_response(c, 99, NULL, 0, -1);
                    close(c);
                }
            }
        }

        // Drain client reads and dispatch complete frames. We mark
        // disconnections in a separate pass so we don't mutate the
        // array while iterating.
        int drop[VS_MAX_CLIENTS];
        int ndrop = 0;
        for (int i = 0; i < VS_MAX_CLIENTS; i++) {
            if (!g_clients[i].used) continue;
            int fd = g_clients[i].fd;
            if (fd < 0) { drop[ndrop++] = i; continue; }
            if (!FD_ISSET(fd, &rfds)) continue;
            if (client_on_readable(i) < 0) drop[ndrop++] = i;
        }
        for (int k = 0; k < ndrop; k++) client_on_disconnect(drop[k]);

        // Drain PTY masters. Each session's pty_fd may have been closed
        // by pump_one_session (shell exited); the next iteration won't
        // re-select it because used/pty_fd gating catches it above.
        for (int i = 0; i < VS_MAX_SESSIONS; i++) {
            if (!g_sessions[i].used) continue;
            int fd = g_sessions[i].pty_fd;
            if (fd < 0) continue;
            if (!FD_ISSET(fd, &rfds)) continue;
            pump_one_session(i);
        }

        // VS-07: periodic checkpoint — every 5s, write all live sessions
        // to disk so crash-resurrection has a recent snapshot if the
        // server itself dies (kill -9, OOM, power loss).
        long tnow = now_ns();
        if (tnow - g_last_ckpt_ns >= VS_CKPT_INTERVAL_NS) {
            g_last_ckpt_ns = tnow;
            for (int i = 0; i < VS_MAX_SESSIONS; i++) {
                if (!g_sessions[i].used) continue;
                if (g_sessions[i].pty_fd < 0) continue; // skip tombstones
                checkpoint_session(&g_sessions[i]);
            }
        }
    }

    // VS-08: graceful shutdown — flush checkpoints for ALL sessions
    // (live and tombstone) so crash-resurrection on next startup has
    // the freshest possible state.
    for (int i = 0; i < VS_MAX_SESSIONS; i++) {
        if (!g_sessions[i].used) continue;
        checkpoint_session(&g_sessions[i]);
    }
    // SIGTERM the shells so they get a clean exit rather than lingering
    // as orphans with a dead master fd.
    for (int i = 0; i < VS_MAX_SESSIONS; i++) {
        if (!g_sessions[i].used) continue;
        if (g_sessions[i].pty_fd >= 0) close(g_sessions[i].pty_fd);
        if (g_sessions[i].shell_pid > 0)
            kill(-g_sessions[i].shell_pid, SIGTERM);
    }
    unlink(VS_SOCK_PATH);
    return 0;
}
