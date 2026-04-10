// void_main.m — Native macOS entry point for VOID terminal
// Compile:
//   clang -framework Metal -framework MetalKit -framework Cocoa -framework CoreText \
//         -framework QuartzCore -o void_app platform/void_main.m platform/void_bridge_metal.m
//
// This is the real main(). It initializes Metal+Cocoa, spawns a shell PTY,
// and drives the event loop directly — no hexa interpreter needed for the core loop.
// hexa is used only for plugin/AI extensions via VOID protocol.

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <util.h>
#include <signal.h>
#include <poll.h>

// Bridge API (from void_bridge_metal.m, linked directly)
extern int  void_app_init(int rows, int cols, int font_size);
extern void void_app_set_title(const char *title);
extern void void_app_set_cell(int row, int col, int ch, int fg, int bg, int flags);
extern void void_app_set_cursor(int row, int col, int visible);
extern void void_app_flush(void);
extern int  void_app_poll(void);
extern int  void_app_read_keys(char *buf, int max_len);
extern int  void_app_get_rows(void);
extern int  void_app_get_cols(void);

// ── Minimal VT state for initial bootstrap ──
// Full VT parsing happens in hexa; this is just enough to show a working shell.

#define GRID_MAX_ROWS 200
#define GRID_MAX_COLS 400

static int g_rows = 35, g_cols = 120;
static int cursor_r = 0, cursor_c = 0;
static int cur_fg = 7, cur_bg = 0, cur_flags = 0;

// Simple cell storage
typedef struct { int ch; int fg; int bg; int flags; } Cell;
static Cell cells[GRID_MAX_ROWS][GRID_MAX_COLS];

static void cell_clear(int r, int c) {
    cells[r][c] = (Cell){' ', 7, 0, 0};
}

static void grid_clear(void) {
    for (int r = 0; r < g_rows; r++)
        for (int c = 0; c < g_cols; c++)
            cell_clear(r, c);
}

static void grid_scroll_up(void) {
    for (int r = 0; r < g_rows - 1; r++)
        memcpy(cells[r], cells[r+1], sizeof(Cell) * g_cols);
    for (int c = 0; c < g_cols; c++)
        cell_clear(g_rows - 1, c);
}

static void grid_put(int ch) {
    if (cursor_c >= g_cols) {
        cursor_c = 0;
        cursor_r++;
        if (cursor_r >= g_rows) {
            grid_scroll_up();
            cursor_r = g_rows - 1;
        }
    }
    cells[cursor_r][cursor_c] = (Cell){ch, cur_fg, cur_bg, cur_flags};
    void_app_set_cell(cursor_r, cursor_c, ch, cur_fg, cur_bg, cur_flags);
    cursor_c++;
}

// ── Minimal VT parser (handles enough for shell prompt) ──

typedef enum { ST_GROUND, ST_ESC, ST_CSI, ST_OSC } VTState;
static VTState vt_state = ST_GROUND;
static char csi_buf[64];
static int csi_len = 0;
static char osc_buf[256];
static int osc_len = 0;

static int parse_int(const char *s, int def) {
    if (!s || !*s) return def;
    int v = 0;
    while (*s >= '0' && *s <= '9') { v = v * 10 + (*s - '0'); s++; }
    return v ? v : def;
}

static void csi_dispatch(char final_ch) {
    csi_buf[csi_len] = 0;
    int params[8] = {0};
    int np = 0;
    char *p = csi_buf;
    // Skip private mode prefix
    int private = 0;
    if (*p == '?') { private = 1; p++; }
    // Parse semicolon-separated params
    while (*p && np < 8) {
        params[np] = 0;
        while (*p >= '0' && *p <= '9') { params[np] = params[np]*10 + (*p-'0'); p++; }
        np++;
        if (*p == ';') p++;
    }
    int n = params[0] ? params[0] : 1;

    switch (final_ch) {
        case 'A': cursor_r = (cursor_r - n < 0) ? 0 : cursor_r - n; break;
        case 'B': cursor_r = (cursor_r + n >= g_rows) ? g_rows-1 : cursor_r + n; break;
        case 'C': cursor_c = (cursor_c + n >= g_cols) ? g_cols-1 : cursor_c + n; break;
        case 'D': cursor_c = (cursor_c - n < 0) ? 0 : cursor_c - n; break;
        case 'H': case 'f': // Cursor position
            cursor_r = (params[0] ? params[0] : 1) - 1;
            cursor_c = (params[1] ? params[1] : 1) - 1;
            if (cursor_r < 0) cursor_r = 0;
            if (cursor_r >= g_rows) cursor_r = g_rows - 1;
            if (cursor_c < 0) cursor_c = 0;
            if (cursor_c >= g_cols) cursor_c = g_cols - 1;
            break;
        case 'J': // Erase display
            if (params[0] == 2 || params[0] == 3) {
                grid_clear();
                for (int r = 0; r < g_rows; r++)
                    for (int c = 0; c < g_cols; c++)
                        void_app_set_cell(r, c, ' ', 7, 0, 0);
            }
            break;
        case 'K': { // Erase line
            int start = (params[0] == 1) ? 0 : cursor_c;
            int end = (params[0] == 0) ? g_cols : ((params[0] == 1) ? cursor_c + 1 : g_cols);
            if (params[0] == 2) start = 0;
            for (int c = start; c < end && c < g_cols; c++) {
                cell_clear(cursor_r, c);
                void_app_set_cell(cursor_r, c, ' ', 7, 0, 0);
            }
            break;
        }
        case 'm': { // SGR
            for (int i = 0; i < np; i++) {
                int v = params[i];
                if (v == 0) { cur_fg = 7; cur_bg = 0; cur_flags = 0; }
                else if (v == 1) cur_flags |= 1;   // bold
                else if (v == 2) cur_flags |= 16;  // dim
                else if (v == 3) cur_flags |= 2;   // italic
                else if (v == 4) cur_flags |= 4;   // underline
                else if (v == 7) cur_flags |= 8;   // inverse
                else if (v == 22) cur_flags &= ~(1|16);
                else if (v == 23) cur_flags &= ~2;
                else if (v == 24) cur_flags &= ~4;
                else if (v == 27) cur_flags &= ~8;
                else if (v >= 30 && v <= 37) cur_fg = v - 30;
                else if (v >= 40 && v <= 47) cur_bg = v - 40;
                else if (v == 39) cur_fg = 7;
                else if (v == 49) cur_bg = 0;
                else if (v >= 90 && v <= 97) cur_fg = v - 90 + 8;
                else if (v >= 100 && v <= 107) cur_bg = v - 100 + 8;
                else if (v == 38 && i+1 < np && params[i+1] == 5 && i+2 < np) {
                    cur_fg = params[i+2]; i += 2;
                }
                else if (v == 48 && i+1 < np && params[i+1] == 5 && i+2 < np) {
                    cur_bg = params[i+2]; i += 2;
                }
                else if (v == 38 && i+1 < np && params[i+1] == 2 && i+4 < np) {
                    cur_fg = 256 + params[i+2]*65536 + params[i+3]*256 + params[i+4]; i += 4;
                }
                else if (v == 48 && i+1 < np && params[i+1] == 2 && i+4 < np) {
                    cur_bg = 256 + params[i+2]*65536 + params[i+3]*256 + params[i+4]; i += 4;
                }
            }
            break;
        }
        case 'h': case 'l': // Mode set/reset — ignore for now
            break;
        case 'r': // Set scroll region — ignore for now
            break;
        case 'n': // Device status report
            break;
    }
}

static void vt_process(const char *data, int len) {
    for (int i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)data[i];

        switch (vt_state) {
            case ST_GROUND:
                if (ch == 0x1b) { vt_state = ST_ESC; }
                else if (ch == '\r') { cursor_c = 0; }
                else if (ch == '\n') {
                    cursor_r++;
                    if (cursor_r >= g_rows) { grid_scroll_up(); cursor_r = g_rows - 1; }
                }
                else if (ch == '\b') { if (cursor_c > 0) cursor_c--; }
                else if (ch == '\t') { cursor_c = (cursor_c + 8) & ~7; if (cursor_c >= g_cols) cursor_c = g_cols - 1; }
                else if (ch == 7) { /* bell — ignore */ }
                else if (ch >= 32) { grid_put(ch); }
                break;

            case ST_ESC:
                if (ch == '[') { vt_state = ST_CSI; csi_len = 0; }
                else if (ch == ']') { vt_state = ST_OSC; osc_len = 0; }
                else if (ch == '(' || ch == ')') { vt_state = ST_GROUND; /* skip charset */ }
                else { vt_state = ST_GROUND; }
                break;

            case ST_CSI:
                if (ch >= 0x40 && ch <= 0x7e) {
                    csi_dispatch(ch);
                    vt_state = ST_GROUND;
                } else if (csi_len < 63) {
                    csi_buf[csi_len++] = ch;
                }
                break;

            case ST_OSC:
                if (ch == 7 || ch == 0x1b) { // BEL or ST
                    osc_buf[osc_len] = 0;
                    // Parse title: "0;title" or "2;title"
                    if (osc_len > 2 && (osc_buf[0] == '0' || osc_buf[0] == '2') && osc_buf[1] == ';') {
                        void_app_set_title(osc_buf + 2);
                    }
                    vt_state = (ch == 0x1b) ? ST_ESC : ST_GROUND;
                } else if (osc_len < 255) {
                    osc_buf[osc_len++] = ch;
                }
                break;
        }
    }
}

// ── Full grid push to bridge ──

static void flush_grid(void) {
    for (int r = 0; r < g_rows; r++)
        for (int c = 0; c < g_cols; c++)
            void_app_set_cell(r, c, cells[r][c].ch, cells[r][c].fg, cells[r][c].bg, cells[r][c].flags);
    void_app_set_cursor(cursor_r, cursor_c, 1);
    void_app_flush();
}

// ── Main ──

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Init Metal window
        void_app_init(g_rows, g_cols, 14);
        void_app_set_title("VOID");
        grid_clear();
        flush_grid();

        // Open PTY + spawn shell
        int master_fd, slave_fd;
        if (openpty(&master_fd, &slave_fd, NULL, NULL, NULL) < 0) {
            fprintf(stderr, "VOID: openpty failed\n");
            return 1;
        }

        pid_t pid = fork();
        if (pid < 0) { fprintf(stderr, "VOID: fork failed\n"); return 1; }
        if (pid == 0) {
            // Child: become session leader, set controlling terminal
            setsid();
            close(master_fd);
            dup2(slave_fd, STDIN_FILENO);
            dup2(slave_fd, STDOUT_FILENO);
            dup2(slave_fd, STDERR_FILENO);
            if (slave_fd > 2) close(slave_fd);

            // Set TERM + window size
            setenv("TERM", "xterm-256color", 1);
            struct winsize ws = { .ws_row = g_rows, .ws_col = g_cols };
            ioctl(STDIN_FILENO, TIOCSWINSZ, &ws);

            const char *shell = getenv("SHELL");
            if (!shell) shell = "/bin/zsh";
            execl(shell, shell, "-l", NULL);
            _exit(1);
        }

        // Parent: set master non-blocking
        close(slave_fd);
        int fl = fcntl(master_fd, F_GETFL, 0);
        fcntl(master_fd, F_SETFL, fl | O_NONBLOCK);

        char read_buf[4096];
        char key_buf[256];
        int running = 1;

        while (running) {
            // 1. Poll Cocoa events
            if (void_app_poll()) { running = 0; break; }

            // 2. Read keyboard from Metal window → write to PTY
            int kn = void_app_read_keys(key_buf, 255);
            if (kn > 0) {
                write(master_fd, key_buf, kn);
            }

            // 3. Read PTY output → VT parse → update cells → flush
            int pn = read(master_fd, read_buf, 4095);
            if (pn > 0) {
                vt_process(read_buf, pn);
                void_app_set_cursor(cursor_r, cursor_c, 1);
                void_app_flush();
            } else if (pn == 0) {
                running = 0; // EOF
            }

            // 4. Check resize
            int nr = void_app_get_rows();
            int nc = void_app_get_cols();
            if (nr != g_rows || nc != g_cols) {
                if (nr >= 5 && nc >= 20 && nr < GRID_MAX_ROWS && nc < GRID_MAX_COLS) {
                    g_rows = nr;
                    g_cols = nc;
                    grid_clear();
                    struct winsize ws = { .ws_row = g_rows, .ws_col = g_cols };
                    ioctl(master_fd, TIOCSWINSZ, &ws);
                    kill(pid, SIGWINCH);
                }
            }

            usleep(8000); // ~120Hz
        }

        // Cleanup
        kill(pid, SIGTERM);
        usleep(100000);
        kill(pid, SIGKILL);
        close(master_fd);
    }
    return 0;
}
