// void_main.m — Native macOS entry point for VOID terminal (production VT emulator)
// Compile:
//   clang -O2 -framework Metal -framework MetalKit -framework Cocoa -framework CoreText \
//         -framework QuartzCore -o void_app platform/void_main.m platform/void_bridge_metal.m
//
// Full VT100/xterm emulator — supports vim, htop, less, zsh, colors, mouse, alt-screen.
// Ported from core/terminal/vt_parser.hexa (678 LOC).

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <util.h>
#include <signal.h>
#include <poll.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>

// ════════════════════════════════════════════════════════════════════
// Bridge API (from void_bridge_metal.m)
// ════════════════════════════════════════════════════════════════════

extern int  void_app_init(int rows, int cols, int font_size);
extern void void_app_set_title(const char *title);
extern void void_app_set_cell(int row, int col, int ch, int fg, int bg, int flags);
extern void void_app_set_cursor(int row, int col, int visible);
extern void void_app_flush(void);
extern int  void_app_poll(void);
extern int  void_app_read_keys(char *buf, int max_len);
extern int  void_app_get_rows(void);
extern int  void_app_get_cols(void);

// ════════════════════════════════════════════════════════════════════
// Constants
// ════════════════════════════════════════════════════════════════════

#define GRID_MAX_ROWS   200
#define GRID_MAX_COLS   400
#define SCROLLBACK_MAX  10000
#define CSI_BUF_MAX     128
#define OSC_BUF_MAX     512
#define DCS_BUF_MAX     512
#define CSI_PARAMS_MAX  32
#define PTY_READ_BUF    16384

// Cell flags
#define FLAG_BOLD       0x01
#define FLAG_ITALIC     0x02
#define FLAG_UNDERLINE  0x04
#define FLAG_INVERSE    0x08
#define FLAG_DIM        0x10
#define FLAG_STRIKETHROUGH 0x20
#define FLAG_BLINK      0x40

// ════════════════════════════════════════════════════════════════════
// Cell
// ════════════════════════════════════════════════════════════════════

typedef struct {
    int ch;
    int fg;
    int bg;
    int flags;
} Cell;

// ════════════════════════════════════════════════════════════════════
// Terminal state
// ════════════════════════════════════════════════════════════════════

static int g_rows = 35, g_cols = 120;
static int master_fd = -1;  // PTY master — needed for DSR/DA responses

// Primary grid
static Cell cells[GRID_MAX_ROWS][GRID_MAX_COLS];
static int  row_dirty[GRID_MAX_ROWS]; // dirty tracking per row

// Alt-screen grid (saved when entering alt screen)
static Cell alt_cells[GRID_MAX_ROWS][GRID_MAX_COLS];
static int  alt_active = 0;

// Scrollback buffer
static Cell scrollback[SCROLLBACK_MAX][GRID_MAX_COLS];
static int  scrollback_count = 0;
static int  scrollback_write = 0;  // circular index

// Cursor
static int cursor_r = 0, cursor_c = 0;
static int cursor_visible = 1;
static int cursor_style = 0;  // DECSCUSR: 0=default, 1-6

// Saved cursor (DECSC / ESC 7)
static int saved_r = 0, saved_c = 0;
static int saved_fg = 7, saved_bg = 0, saved_flags = 0;

// Alt-screen saved cursor
static int alt_saved_r = 0, alt_saved_c = 0;

// Current attributes
static int cur_fg = 7, cur_bg = 0, cur_flags = 0;

// Scroll region
static int scroll_top = 0, scroll_bottom = -1;  // -1 = g_rows - 1

// Modes
static int mode_decckm    = 0;  // ?1  application cursor keys
static int mode_autowrap  = 1;  // ?7  auto-wrap (default on)
static int mode_cursor_blink = 0; // ?12
static int mode_origin    = 0;  // ?6  origin mode
static int mode_bracketed_paste = 0; // ?2004

// Mouse modes
typedef enum {
    MOUSE_NONE    = 0,
    MOUSE_BASIC   = 1000,
    MOUSE_BUTTON  = 1002,
    MOUSE_ANY     = 1003
} MouseMode;
static MouseMode mouse_mode = MOUSE_NONE;
static int mouse_sgr = 0;  // ?1006 SGR extended mouse

// Wrap-next flag: if true, the next printable char wraps to next line first
static int wrap_next = 0;

// ════════════════════════════════════════════════════════════════════
// VT Parser state
// ════════════════════════════════════════════════════════════════════

typedef enum {
    ST_GROUND,
    ST_ESC,
    ST_CSI,
    ST_OSC,
    ST_DCS,
    ST_CHARSET
} VTState;

static VTState vt_state = ST_GROUND;

// CSI accumulator
static char csi_buf[CSI_BUF_MAX];
static int  csi_len = 0;
static int  csi_private = 0;   // '?' or '>' prefix
static int  csi_intermediate = 0; // intermediate byte (e.g., SP for DECSCUSR)

// OSC accumulator
static char osc_buf[OSC_BUF_MAX];
static int  osc_len = 0;

// DCS accumulator
static char dcs_buf[DCS_BUF_MAX];
static int  dcs_len = 0;

// ════════════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════════════

static inline int clamp(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static inline int scroll_bot(void) {
    return (scroll_bottom < 0) ? (g_rows - 1) : scroll_bottom;
}

static void mark_dirty(int r) {
    if (r >= 0 && r < GRID_MAX_ROWS) row_dirty[r] = 1;
}

static void mark_all_dirty(void) {
    for (int r = 0; r < g_rows; r++) row_dirty[r] = 1;
}

// Write response string to PTY master (for DSR, DA)
static void pty_reply(const char *s) {
    if (master_fd >= 0 && s) {
        write(master_fd, s, strlen(s));
    }
}

// ════════════════════════════════════════════════════════════════════
// Cell / Grid operations
// ════════════════════════════════════════════════════════════════════

static inline void cell_clear(int r, int c) {
    cells[r][c] = (Cell){' ', cur_fg, cur_bg, 0};
}

static inline void cell_clear_default(int r, int c) {
    cells[r][c] = (Cell){' ', 7, 0, 0};
}

static void row_clear(int r) {
    for (int c = 0; c < g_cols; c++)
        cell_clear(r, c);
    mark_dirty(r);
}

static void row_clear_default(int r) {
    for (int c = 0; c < g_cols; c++)
        cell_clear_default(r, c);
    mark_dirty(r);
}

static void grid_clear(void) {
    for (int r = 0; r < g_rows; r++)
        row_clear_default(r);
}

// ── Scrollback ──

static void scrollback_push(int row) {
    memcpy(scrollback[scrollback_write], cells[row], sizeof(Cell) * g_cols);
    scrollback_write = (scrollback_write + 1) % SCROLLBACK_MAX;
    if (scrollback_count < SCROLLBACK_MAX) scrollback_count++;
}

// ── Scroll within region ──

static void grid_scroll_up(int n) {
    int top = scroll_top;
    int bot = scroll_bot();
    if (n <= 0) return;
    if (n > bot - top + 1) n = bot - top + 1;

    // Push scrolled-off lines to scrollback if region is full screen
    if (top == 0) {
        for (int i = 0; i < n; i++)
            scrollback_push(i);
    }

    // Shift lines up
    for (int r = top; r <= bot - n; r++) {
        memcpy(cells[r], cells[r + n], sizeof(Cell) * g_cols);
        mark_dirty(r);
    }
    // Clear bottom n lines
    for (int r = bot - n + 1; r <= bot; r++)
        row_clear(r);
}

static void grid_scroll_down(int n) {
    int top = scroll_top;
    int bot = scroll_bot();
    if (n <= 0) return;
    if (n > bot - top + 1) n = bot - top + 1;

    // Shift lines down
    for (int r = bot; r >= top + n; r--) {
        memcpy(cells[r], cells[r - n], sizeof(Cell) * g_cols);
        mark_dirty(r);
    }
    // Clear top n lines
    for (int r = top; r < top + n; r++)
        row_clear(r);
}

// ── Insert / delete lines at cursor ──

static void grid_insert_lines(int n) {
    int top = cursor_r;
    int bot = scroll_bot();
    if (top < scroll_top || top > bot) return;
    if (n > bot - top + 1) n = bot - top + 1;

    // Shift lines down from cursor
    for (int r = bot; r >= top + n; r--) {
        memcpy(cells[r], cells[r - n], sizeof(Cell) * g_cols);
        mark_dirty(r);
    }
    for (int r = top; r < top + n; r++)
        row_clear(r);
}

static void grid_delete_lines(int n) {
    int top = cursor_r;
    int bot = scroll_bot();
    if (top < scroll_top || top > bot) return;
    if (n > bot - top + 1) n = bot - top + 1;

    // Shift lines up from cursor
    for (int r = top; r <= bot - n; r++) {
        memcpy(cells[r], cells[r + n], sizeof(Cell) * g_cols);
        mark_dirty(r);
    }
    for (int r = bot - n + 1; r <= bot; r++)
        row_clear(r);
}

// ── Insert / delete / erase chars at cursor ──

static void grid_insert_chars(int n) {
    int r = cursor_r, c = cursor_c;
    if (n > g_cols - c) n = g_cols - c;
    // Shift right
    for (int i = g_cols - 1; i >= c + n; i--)
        cells[r][i] = cells[r][i - n];
    for (int i = c; i < c + n && i < g_cols; i++)
        cell_clear(r, i);
    mark_dirty(r);
}

static void grid_delete_chars(int n) {
    int r = cursor_r, c = cursor_c;
    if (n > g_cols - c) n = g_cols - c;
    // Shift left
    for (int i = c; i < g_cols - n; i++)
        cells[r][i] = cells[r][i + n];
    for (int i = g_cols - n; i < g_cols; i++)
        cell_clear(r, i);
    mark_dirty(r);
}

static void grid_erase_chars(int n) {
    int r = cursor_r, c = cursor_c;
    for (int i = c; i < c + n && i < g_cols; i++)
        cell_clear(r, i);
    mark_dirty(r);
}

// ── Alt-screen ──

static void alt_screen_enter(void) {
    if (alt_active) return;
    alt_active = 1;
    memcpy(alt_cells, cells, sizeof(cells));
    alt_saved_r = cursor_r;
    alt_saved_c = cursor_c;
    grid_clear();
    mark_all_dirty();
}

static void alt_screen_leave(void) {
    if (!alt_active) return;
    alt_active = 0;
    memcpy(cells, alt_cells, sizeof(cells));
    cursor_r = alt_saved_r;
    cursor_c = alt_saved_c;
    mark_all_dirty();
}

// ── Put character at cursor ──

static void grid_put(int ch) {
    // Handle wrap-next: deferred wrap from previous char at end of line
    if (wrap_next) {
        wrap_next = 0;
        cursor_c = 0;
        cursor_r++;
        if (cursor_r > scroll_bot()) {
            grid_scroll_up(1);
            cursor_r = scroll_bot();
        }
    }

    cells[cursor_r][cursor_c] = (Cell){ch, cur_fg, cur_bg, cur_flags};
    mark_dirty(cursor_r);

    cursor_c++;
    if (cursor_c >= g_cols) {
        if (mode_autowrap) {
            // Deferred wrap: stay at last column, wrap on next printable
            cursor_c = g_cols - 1;
            wrap_next = 1;
        } else {
            cursor_c = g_cols - 1;
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// CSI parameter parsing
// ════════════════════════════════════════════════════════════════════

static int csi_params[CSI_PARAMS_MAX];
static int csi_param_count = 0;

static void csi_parse_params(void) {
    csi_buf[csi_len] = 0;
    csi_param_count = 0;
    csi_private = 0;
    csi_intermediate = 0;

    char *p = csi_buf;

    // Check for private mode prefix
    if (*p == '?') { csi_private = '?'; p++; }
    else if (*p == '>') { csi_private = '>'; p++; }

    // Parse params
    while (*p && csi_param_count < CSI_PARAMS_MAX) {
        if (*p >= '0' && *p <= '9') {
            csi_params[csi_param_count] = 0;
            while (*p >= '0' && *p <= '9') {
                csi_params[csi_param_count] = csi_params[csi_param_count] * 10 + (*p - '0');
                p++;
            }
            csi_param_count++;
        } else if (*p == ';') {
            if (csi_param_count == 0) {
                csi_params[csi_param_count++] = 0; // missing param = 0
            }
            p++;
            // If next is ; or end, push 0
            if (*p == ';' || !*p || *p == ' ') {
                csi_params[csi_param_count++] = 0;
            }
        } else if (*p == ' ') {
            csi_intermediate = ' ';
            p++;
        } else {
            p++; // skip unknown intermediates
        }
    }
}

static inline int csi_param(int idx, int def) {
    if (idx < csi_param_count && csi_params[idx] != 0) return csi_params[idx];
    return def;
}

// ════════════════════════════════════════════════════════════════════
// CSI dispatch
// ════════════════════════════════════════════════════════════════════

static void csi_dispatch(char final_ch) {
    csi_parse_params();

    int n  = csi_param(0, 1);
    int n0 = csi_param(0, 0); // 0-default variant

    switch (final_ch) {

    // ── Cursor movement ──

    case 'A': // CUU — cursor up
        cursor_r = clamp(cursor_r - n, 0, g_rows - 1);
        wrap_next = 0;
        break;

    case 'B': // CUD — cursor down
        cursor_r = clamp(cursor_r + n, 0, g_rows - 1);
        wrap_next = 0;
        break;

    case 'C': // CUF — cursor forward
        cursor_c = clamp(cursor_c + n, 0, g_cols - 1);
        wrap_next = 0;
        break;

    case 'D': // CUB — cursor back
        cursor_c = clamp(cursor_c - n, 0, g_cols - 1);
        wrap_next = 0;
        break;

    case 'E': // CNL — cursor next line
        cursor_c = 0;
        cursor_r = clamp(cursor_r + n, 0, g_rows - 1);
        wrap_next = 0;
        break;

    case 'F': // CPL — cursor prev line
        cursor_c = 0;
        cursor_r = clamp(cursor_r - n, 0, g_rows - 1);
        wrap_next = 0;
        break;

    case 'G': // CHA — cursor horizontal absolute
        cursor_c = clamp(n - 1, 0, g_cols - 1);
        wrap_next = 0;
        break;

    case 'H': // CUP — cursor position
    case 'f': // HVP — same as CUP
        cursor_r = clamp(csi_param(0, 1) - 1, 0, g_rows - 1);
        cursor_c = clamp(csi_param(1, 1) - 1, 0, g_cols - 1);
        wrap_next = 0;
        break;

    case 'd': // VPA — vertical position absolute
        cursor_r = clamp(n - 1, 0, g_rows - 1);
        wrap_next = 0;
        break;

    // ── Erase ──

    case 'J': { // ED — erase display
        int mode = n0;
        if (mode == 0) {
            // Erase from cursor to end
            for (int c = cursor_c; c < g_cols; c++) cell_clear(cursor_r, c);
            mark_dirty(cursor_r);
            for (int r = cursor_r + 1; r < g_rows; r++) row_clear(r);
        } else if (mode == 1) {
            // Erase from start to cursor
            for (int r = 0; r < cursor_r; r++) row_clear(r);
            for (int c = 0; c <= cursor_c; c++) cell_clear(cursor_r, c);
            mark_dirty(cursor_r);
        } else if (mode == 2 || mode == 3) {
            // Erase entire display
            grid_clear();
        }
        break;
    }

    case 'K': { // EL — erase line
        int mode = n0;
        int r = cursor_r;
        if (mode == 0) {
            for (int c = cursor_c; c < g_cols; c++) cell_clear(r, c);
        } else if (mode == 1) {
            for (int c = 0; c <= cursor_c; c++) cell_clear(r, c);
        } else if (mode == 2) {
            for (int c = 0; c < g_cols; c++) cell_clear(r, c);
        }
        mark_dirty(r);
        break;
    }

    case 'X': // ECH — erase characters
        grid_erase_chars(n);
        break;

    // ── Insert / delete lines ──

    case 'L': // IL — insert lines
        grid_insert_lines(n);
        break;

    case 'M': // DL — delete lines
        grid_delete_lines(n);
        break;

    // ── Insert / delete chars ──

    case '@': // ICH — insert blank characters
        grid_insert_chars(n);
        break;

    case 'P': // DCH — delete characters
        grid_delete_chars(n);
        break;

    // ── Scroll ──

    case 'S': // SU — scroll up
        grid_scroll_up(n);
        break;

    case 'T': // SD — scroll down
        grid_scroll_down(n);
        break;

    case 'r': { // DECSTBM — set scroll region
        int top = csi_param(0, 1) - 1;
        int bot = csi_param(1, g_rows) - 1;
        top = clamp(top, 0, g_rows - 1);
        bot = clamp(bot, 0, g_rows - 1);
        if (top < bot) {
            scroll_top = top;
            scroll_bottom = bot;
        } else {
            scroll_top = 0;
            scroll_bottom = -1; // full screen
        }
        // Reset cursor to home
        cursor_r = mode_origin ? scroll_top : 0;
        cursor_c = 0;
        wrap_next = 0;
        break;
    }

    // ── SGR — Select Graphic Rendition ──

    case 'm': {
        if (csi_param_count == 0) {
            // ESC[m = reset
            cur_fg = 7; cur_bg = 0; cur_flags = 0;
            break;
        }
        for (int i = 0; i < csi_param_count; i++) {
            int v = csi_params[i];
            if (v == 0)       { cur_fg = 7; cur_bg = 0; cur_flags = 0; }
            else if (v == 1)  cur_flags |= FLAG_BOLD;
            else if (v == 2)  cur_flags |= FLAG_DIM;
            else if (v == 3)  cur_flags |= FLAG_ITALIC;
            else if (v == 4)  cur_flags |= FLAG_UNDERLINE;
            else if (v == 5 || v == 6) cur_flags |= FLAG_BLINK;
            else if (v == 7)  cur_flags |= FLAG_INVERSE;
            else if (v == 9)  cur_flags |= FLAG_STRIKETHROUGH;
            else if (v == 21) cur_flags |= FLAG_UNDERLINE; // double underline → underline
            else if (v == 22) cur_flags &= ~(FLAG_BOLD | FLAG_DIM);
            else if (v == 23) cur_flags &= ~FLAG_ITALIC;
            else if (v == 24) cur_flags &= ~FLAG_UNDERLINE;
            else if (v == 25) cur_flags &= ~FLAG_BLINK;
            else if (v == 27) cur_flags &= ~FLAG_INVERSE;
            else if (v == 29) cur_flags &= ~FLAG_STRIKETHROUGH;
            else if (v >= 30 && v <= 37) cur_fg = v - 30;
            else if (v == 38) {
                // Extended foreground
                if (i + 1 < csi_param_count && csi_params[i+1] == 5 && i + 2 < csi_param_count) {
                    cur_fg = csi_params[i+2];
                    i += 2;
                } else if (i + 1 < csi_param_count && csi_params[i+1] == 2 && i + 4 < csi_param_count) {
                    int r = csi_params[i+2] & 0xFF;
                    int g = csi_params[i+3] & 0xFF;
                    int b = csi_params[i+4] & 0xFF;
                    cur_fg = 256 + (r << 16) + (g << 8) + b;
                    i += 4;
                }
            }
            else if (v == 39) cur_fg = 7; // default fg
            else if (v >= 40 && v <= 47) cur_bg = v - 40;
            else if (v == 48) {
                // Extended background
                if (i + 1 < csi_param_count && csi_params[i+1] == 5 && i + 2 < csi_param_count) {
                    cur_bg = csi_params[i+2];
                    i += 2;
                } else if (i + 1 < csi_param_count && csi_params[i+1] == 2 && i + 4 < csi_param_count) {
                    int r = csi_params[i+2] & 0xFF;
                    int g = csi_params[i+3] & 0xFF;
                    int b = csi_params[i+4] & 0xFF;
                    cur_bg = 256 + (r << 16) + (g << 8) + b;
                    i += 4;
                }
            }
            else if (v == 49) cur_bg = 0; // default bg
            else if (v >= 90 && v <= 97)   cur_fg = v - 90 + 8;
            else if (v >= 100 && v <= 107) cur_bg = v - 100 + 8;
        }
        break;
    }

    // ── Modes (DECSET / DECRST) ──

    case 'h': // SM — set mode
        if (csi_private == '?') {
            for (int i = 0; i < csi_param_count; i++) {
                switch (csi_params[i]) {
                    case 1:    mode_decckm = 1; break;
                    case 6:    mode_origin = 1; cursor_r = scroll_top; cursor_c = 0; break;
                    case 7:    mode_autowrap = 1; break;
                    case 12:   mode_cursor_blink = 1; break;
                    case 25:   cursor_visible = 1; break;
                    case 47:
                    case 1047: alt_screen_enter(); break;
                    case 1049:
                        // Save cursor, then enter alt screen
                        saved_r = cursor_r; saved_c = cursor_c;
                        saved_fg = cur_fg; saved_bg = cur_bg; saved_flags = cur_flags;
                        alt_screen_enter();
                        break;
                    case 1000: mouse_mode = MOUSE_BASIC; break;
                    case 1002: mouse_mode = MOUSE_BUTTON; break;
                    case 1003: mouse_mode = MOUSE_ANY; break;
                    case 1006: mouse_sgr = 1; break;
                    case 2004: mode_bracketed_paste = 1; break;
                }
            }
        }
        break;

    case 'l': // RM — reset mode
        if (csi_private == '?') {
            for (int i = 0; i < csi_param_count; i++) {
                switch (csi_params[i]) {
                    case 1:    mode_decckm = 0; break;
                    case 6:    mode_origin = 0; cursor_r = 0; cursor_c = 0; break;
                    case 7:    mode_autowrap = 0; break;
                    case 12:   mode_cursor_blink = 0; break;
                    case 25:   cursor_visible = 0; break;
                    case 47:
                    case 1047: alt_screen_leave(); break;
                    case 1049:
                        alt_screen_leave();
                        // Restore cursor
                        cursor_r = saved_r; cursor_c = saved_c;
                        cur_fg = saved_fg; cur_bg = saved_bg; cur_flags = saved_flags;
                        break;
                    case 1000:
                    case 1002:
                    case 1003: mouse_mode = MOUSE_NONE; break;
                    case 1006: mouse_sgr = 0; break;
                    case 2004: mode_bracketed_paste = 0; break;
                }
            }
        }
        break;

    // ── Save / restore cursor (ANSI.SYS) ──

    case 's': // SCP — save cursor position
        saved_r = cursor_r; saved_c = cursor_c;
        saved_fg = cur_fg; saved_bg = cur_bg; saved_flags = cur_flags;
        break;

    case 'u': // RCP — restore cursor position
        cursor_r = clamp(saved_r, 0, g_rows - 1);
        cursor_c = clamp(saved_c, 0, g_cols - 1);
        cur_fg = saved_fg; cur_bg = saved_bg; cur_flags = saved_flags;
        wrap_next = 0;
        break;

    // ── Device queries ──

    case 'n': // DSR — device status report
        if (csi_params[0] == 6) {
            char resp[32];
            snprintf(resp, sizeof(resp), "\033[%d;%dR", cursor_r + 1, cursor_c + 1);
            pty_reply(resp);
        } else if (csi_params[0] == 5) {
            pty_reply("\033[0n"); // terminal OK
        }
        break;

    case 'c': // DA — device attributes
        if (csi_private == '>') {
            // DA2 — secondary device attributes
            pty_reply("\033[>1;100;0c");
        } else if (n0 == 0) {
            // DA1 — primary device attributes
            pty_reply("\033[?62;1;6;22c");
        }
        break;

    // ── Cursor style (DECSCUSR) — requires SP intermediate ──

    case 'q':
        if (csi_intermediate == ' ') {
            cursor_style = n0;
            // 0,1 = blinking block, 2 = steady block
            // 3 = blinking underline, 4 = steady underline
            // 5 = blinking bar, 6 = steady bar
        }
        break;

    // ── Tab clear / other ──

    case 'g': // TBC — tab clear (ignore for now, tabs still work as fixed 8)
        break;

    case 't': // Window manipulation (mostly ignored)
        break;

    } // end switch
}

// ════════════════════════════════════════════════════════════════════
// OSC dispatch
// ════════════════════════════════════════════════════════════════════

static void osc_dispatch(void) {
    osc_buf[osc_len] = 0;

    // Find Ps separator
    int ps = -1;
    int sep = -1;
    for (int i = 0; i < osc_len; i++) {
        if (osc_buf[i] == ';') { sep = i; break; }
    }

    if (sep > 0) {
        // Parse Ps
        ps = 0;
        for (int i = 0; i < sep; i++) {
            if (osc_buf[i] >= '0' && osc_buf[i] <= '9')
                ps = ps * 10 + (osc_buf[i] - '0');
        }

        char *payload = osc_buf + sep + 1;

        switch (ps) {
            case 0: // Set icon name + title
            case 1: // Set icon name
            case 2: // Set title
                void_app_set_title(payload);
                break;
            // 777 = VOID protocol extension (future)
        }
    }
}

// ════════════════════════════════════════════════════════════════════
// ESC-level dispatch (single char after ESC, not CSI/OSC/DCS)
// ════════════════════════════════════════════════════════════════════

static void esc_dispatch(unsigned char ch) {
    switch (ch) {
        case '7': // DECSC — save cursor
            saved_r = cursor_r; saved_c = cursor_c;
            saved_fg = cur_fg; saved_bg = cur_bg; saved_flags = cur_flags;
            break;
        case '8': // DECRC — restore cursor
            cursor_r = clamp(saved_r, 0, g_rows - 1);
            cursor_c = clamp(saved_c, 0, g_cols - 1);
            cur_fg = saved_fg; cur_bg = saved_bg; cur_flags = saved_flags;
            wrap_next = 0;
            break;
        case 'D': // IND — index (move down, scroll if at bottom)
            if (cursor_r == scroll_bot()) {
                grid_scroll_up(1);
            } else if (cursor_r < g_rows - 1) {
                cursor_r++;
            }
            break;
        case 'M': // RI — reverse index (move up, scroll if at top)
            if (cursor_r == scroll_top) {
                grid_scroll_down(1);
            } else if (cursor_r > 0) {
                cursor_r--;
            }
            break;
        case 'E': // NEL — next line
            cursor_c = 0;
            if (cursor_r == scroll_bot()) {
                grid_scroll_up(1);
            } else if (cursor_r < g_rows - 1) {
                cursor_r++;
            }
            break;
        case 'H': // HTS — horizontal tab set (ignore, use fixed tabs)
            break;
        case 'c': // RIS — full reset
            cur_fg = 7; cur_bg = 0; cur_flags = 0;
            cursor_r = 0; cursor_c = 0;
            cursor_visible = 1;
            scroll_top = 0; scroll_bottom = -1;
            mode_decckm = 0; mode_autowrap = 1; mode_origin = 0;
            mode_bracketed_paste = 0;
            mouse_mode = MOUSE_NONE; mouse_sgr = 0;
            wrap_next = 0;
            if (alt_active) alt_screen_leave();
            grid_clear();
            break;
        case '=': // DECKPAM — keypad application mode (noted, no action needed)
            break;
        case '>': // DECKPNM — keypad numeric mode
            break;
    }
}

// ════════════════════════════════════════════════════════════════════
// Main VT processor — 6-state parser
// ════════════════════════════════════════════════════════════════════

static void vt_process(const char *data, int len) {
    for (int i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)data[i];

        switch (vt_state) {

        // ── Ground state ──
        case ST_GROUND:
            if (ch == 0x1B) {
                vt_state = ST_ESC;
            } else if (ch == '\r') {
                cursor_c = 0;
                wrap_next = 0;
            } else if (ch == '\n' || ch == '\v' || ch == '\f') {
                // LF, VT, FF all treated as newline
                if (cursor_r == scroll_bot()) {
                    grid_scroll_up(1);
                } else if (cursor_r < g_rows - 1) {
                    cursor_r++;
                }
                wrap_next = 0;
            } else if (ch == '\b') {
                if (cursor_c > 0) cursor_c--;
                wrap_next = 0;
            } else if (ch == '\t') {
                // Tab to next 8-col stop
                int next = (cursor_c + 8) & ~7;
                cursor_c = (next >= g_cols) ? g_cols - 1 : next;
                wrap_next = 0;
            } else if (ch == 0x07) {
                // BEL — could trigger visual bell via bridge
            } else if (ch == 0x0E) {
                // SO — shift out (G1 charset, ignore)
            } else if (ch == 0x0F) {
                // SI — shift in (G0 charset, ignore)
            } else if (ch >= 32) {
                grid_put(ch);
            }
            break;

        // ── ESC state ──
        case ST_ESC:
            if (ch == '[') {
                vt_state = ST_CSI;
                csi_len = 0;
            } else if (ch == ']') {
                vt_state = ST_OSC;
                osc_len = 0;
            } else if (ch == 'P') {
                vt_state = ST_DCS;
                dcs_len = 0;
            } else if (ch == '(' || ch == ')' || ch == '*' || ch == '+') {
                // Charset designation — consume next byte
                vt_state = ST_CHARSET;
            } else if (ch == '\\') {
                // ST (string terminator) — end of OSC/DCS if we got here
                vt_state = ST_GROUND;
            } else {
                // Single-char ESC sequence
                esc_dispatch(ch);
                vt_state = ST_GROUND;
            }
            break;

        // ── CSI state ──
        case ST_CSI:
            if (ch >= 0x40 && ch <= 0x7E) {
                // Final byte
                csi_dispatch(ch);
                vt_state = ST_GROUND;
            } else if (csi_len < CSI_BUF_MAX - 1) {
                // Parameter / intermediate byte
                csi_buf[csi_len++] = ch;
            }
            break;

        // ── OSC state ──
        case ST_OSC:
            if (ch == 0x07) {
                // BEL terminates OSC
                osc_dispatch();
                vt_state = ST_GROUND;
            } else if (ch == 0x1B) {
                // Possible ST (ESC \)
                // Peek: dispatch and go to ESC to catch the backslash
                osc_dispatch();
                vt_state = ST_ESC;
            } else if (osc_len < OSC_BUF_MAX - 1) {
                osc_buf[osc_len++] = ch;
            }
            break;

        // ── DCS state ──
        case ST_DCS:
            if (ch == 0x1B) {
                // ST coming (ESC \)
                vt_state = ST_ESC;
            } else if (ch == 0x07) {
                // Some terminals use BEL to end DCS too
                vt_state = ST_GROUND;
            } else if (dcs_len < DCS_BUF_MAX - 1) {
                dcs_buf[dcs_len++] = ch;
            }
            break;

        // ── Charset designation (consume one byte) ──
        case ST_CHARSET:
            // ch is the charset designator (B=ASCII, 0=DEC graphics, etc.)
            // We don't implement charset switching, just consume and return
            vt_state = ST_GROUND;
            break;

        } // end switch(vt_state)
    }
}

// ════════════════════════════════════════════════════════════════════
// Dirty-tracking flush to bridge
// ════════════════════════════════════════════════════════════════════

static void flush_dirty(void) {
    for (int r = 0; r < g_rows; r++) {
        if (!row_dirty[r]) continue;
        row_dirty[r] = 0;
        for (int c = 0; c < g_cols; c++) {
            Cell *cell = &cells[r][c];
            void_app_set_cell(r, c, cell->ch, cell->fg, cell->bg, cell->flags);
        }
    }
    void_app_set_cursor(cursor_r, cursor_c, cursor_visible);
    void_app_flush();
}

static void flush_full(void) {
    mark_all_dirty();
    flush_dirty();
}

// ════════════════════════════════════════════════════════════════════
// Keyboard handling — translate keys with mode awareness
// ════════════════════════════════════════════════════════════════════

// Rewrite arrow keys when DECCKM is set:
// Normal:  ESC [ A/B/C/D
// DECCKM:  ESC O A/B/C/D
static int translate_keys(char *buf, int len, char *out, int max_out) {
    int olen = 0;

    for (int i = 0; i < len && olen < max_out - 4; ) {
        // Check for ESC [ A/B/C/D pattern
        if (mode_decckm && i + 2 < len
            && buf[i] == 0x1B && buf[i+1] == '['
            && (buf[i+2] == 'A' || buf[i+2] == 'B' || buf[i+2] == 'C' || buf[i+2] == 'D')) {
            out[olen++] = 0x1B;
            out[olen++] = 'O';  // Replace [ with O
            out[olen++] = buf[i+2];
            i += 3;
        } else {
            out[olen++] = buf[i++];
        }
    }
    return olen;
}

// ════════════════════════════════════════════════════════════════════
// Resize handler
// ════════════════════════════════════════════════════════════════════

static void handle_resize(int new_rows, int new_cols, pid_t pid) {
    if (new_rows < 2 || new_cols < 2) return;
    if (new_rows >= GRID_MAX_ROWS || new_cols >= GRID_MAX_COLS) return;
    if (new_rows == g_rows && new_cols == g_cols) return;

    int old_rows = g_rows;
    int old_cols = g_cols;

    // Save current content that fits in new dimensions
    Cell saved[GRID_MAX_ROWS][GRID_MAX_COLS];
    memcpy(saved, cells, sizeof(cells));

    g_rows = new_rows;
    g_cols = new_cols;

    // Clear and copy what fits
    grid_clear();
    int copy_rows = (old_rows < new_rows) ? old_rows : new_rows;
    int copy_cols = (old_cols < new_cols) ? old_cols : new_cols;
    for (int r = 0; r < copy_rows; r++) {
        memcpy(cells[r], saved[r], sizeof(Cell) * copy_cols);
    }

    // Adjust scroll region
    if (scroll_bottom >= new_rows || scroll_bottom < 0) {
        scroll_bottom = -1; // reset to full screen
    }
    if (scroll_top >= new_rows) scroll_top = 0;

    // Clamp cursor
    cursor_r = clamp(cursor_r, 0, g_rows - 1);
    cursor_c = clamp(cursor_c, 0, g_cols - 1);

    // Tell the PTY
    struct winsize ws = { .ws_row = g_rows, .ws_col = g_cols };
    ioctl(master_fd, TIOCSWINSZ, &ws);
    if (pid > 0) kill(pid, SIGWINCH);

    mark_all_dirty();
}

// ════════════════════════════════════════════════════════════════════
// Main
// ════════════════════════════════════════════════════════════════════

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Initialize Metal window
        void_app_init(g_rows, g_cols, 14);
        void_app_set_title("VOID");
        grid_clear();
        flush_full();

        // Open PTY + spawn shell
        int slave_fd;
        if (openpty(&master_fd, &slave_fd, NULL, NULL, NULL) < 0) {
            fprintf(stderr, "VOID: openpty failed\n");
            return 1;
        }

        pid_t pid = fork();
        if (pid < 0) { fprintf(stderr, "VOID: fork failed\n"); return 1; }

        if (pid == 0) {
            // ── Child process ──
            setsid();
            close(master_fd);

            // Set controlling terminal
            ioctl(slave_fd, TIOCSCTTY, 0);

            dup2(slave_fd, STDIN_FILENO);
            dup2(slave_fd, STDOUT_FILENO);
            dup2(slave_fd, STDERR_FILENO);
            if (slave_fd > 2) close(slave_fd);

            // Environment
            setenv("TERM", "xterm-256color", 1);
            setenv("COLORTERM", "truecolor", 1);
            setenv("LANG", "en_US.UTF-8", 1);

            // Set window size
            struct winsize ws = { .ws_row = g_rows, .ws_col = g_cols };
            ioctl(STDIN_FILENO, TIOCSWINSZ, &ws);

            // Use login(1) for proper macOS environment setup (same as Terminal.app)
            // This runs /etc/zprofile → path_helper → user .zprofile/.zshrc
            // so homebrew PATH and all user config are picked up correctly
            const char *user = getenv("USER");
            if (!user) user = getenv("LOGNAME");
            if (!user) user = "ghost";
            execl("/usr/bin/login", "login", "-fp", user, NULL);
            _exit(1);
        }

        // ── Parent process ──
        close(slave_fd);

        // Set master non-blocking
        int fl = fcntl(master_fd, F_GETFL, 0);
        fcntl(master_fd, F_SETFL, fl | O_NONBLOCK);

        char read_buf[PTY_READ_BUF];
        char key_buf[512];
        char translated[512];
        int running = 1;
        int needs_flush = 0;

        while (running) {
            // 1. Poll Cocoa events (handles NSApp runloop)
            if (void_app_poll()) {
                running = 0;
                break;
            }

            // 2. Read keyboard → translate → write to PTY
            int kn = void_app_read_keys(key_buf, 511);
            if (kn > 0) {
                int tn = translate_keys(key_buf, kn, translated, 511);

                // Bracketed paste: if input contains a paste marker (TODO: detect from bridge)
                // For now, just write through
                write(master_fd, translated, tn);
            }

            // 3. Read PTY output → VT parse → mark dirty
            int total_read = 0;
            for (;;) {
                int pn = (int)read(master_fd, read_buf, PTY_READ_BUF - 1);
                if (pn > 0) {
                    vt_process(read_buf, pn);
                    needs_flush = 1;
                    total_read += pn;
                    // Read more if available, but cap to avoid stalling the event loop
                    if (total_read > PTY_READ_BUF * 4) break;
                } else if (pn == 0) {
                    running = 0; // EOF — shell exited
                    break;
                } else {
                    // EAGAIN / EWOULDBLOCK — no more data
                    if (errno != EAGAIN && errno != EWOULDBLOCK) {
                        running = 0; // real error
                    }
                    break;
                }
            }

            // 4. Flush dirty rows to bridge
            if (needs_flush) {
                flush_dirty();
                needs_flush = 0;
            }

            // 5. Check resize
            int nr = void_app_get_rows();
            int nc = void_app_get_cols();
            if (nr != g_rows || nc != g_cols) {
                handle_resize(nr, nc, pid);
                flush_full();
            }

            // ~120Hz
            usleep(8000);
        }

        // ── Cleanup ──
        kill(pid, SIGTERM);
        usleep(100000);
        kill(pid, SIGKILL);
        close(master_fd);
        master_fd = -1;
    }
    return 0;
}
