// examples/appkit_helpers.m — minimal AppKit wrappers for hexa terminal.
// Compiles with: clang -ObjC -framework Cocoa
//
// Exposes plain C symbols (hexa_appkit_*) that hexa extern fn can call.
// Scope: open an NSWindow, pump the event loop for a bounded duration,
// exit cleanly. No drawing yet — that's the next layer.
//
// 2026-04-11 (hexa terminal 선행작업 #9).

#import <Cocoa/Cocoa.h>
#include <stdio.h>

static NSWindow* g_window = nil;

// ---------------------------------------------------------------------------
// HexaDrawView — NSView subclass that draws "HEXA TERM v1" in monospace
// white on a black background via Core Text (NSString drawAtPoint).
// L3 entry precursor: validates the drawRect render path before wiring up
// the full screen-buffer → glyph pipeline.
// ---------------------------------------------------------------------------
@interface HexaDrawView : NSView
@end

@implementation HexaDrawView
- (BOOL)acceptsFirstResponder {
    return YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor blackColor] setFill];
    NSRectFill(dirtyRect);

    NSFont* font = [NSFont userFixedPitchFontOfSize:14];
    NSDictionary* attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    NSString* msg = @"HEXA TERM v1";
    [msg drawAtPoint:NSMakePoint(10, 10) withAttributes:attrs];
}
@end

// Initialize NSApplication and set its activation policy so the window
// becomes a real, focusable window even when launched from a terminal.
// Returns 0 on success.
long hexa_appkit_init(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
    }
    return 0;
}

// Create and show a titled, closable, resizable window of given size.
// Title is hardcoded to "hexa term v1" to sidestep hexa extern
// string-arg inference. Returns 0 on success.
long hexa_appkit_window_open_default(long w, long h) {
    @autoreleasepool {
        NSRect frame = NSMakeRect(100.0, 100.0, (CGFloat)w, (CGFloat)h);
        NSWindowStyleMask style = NSWindowStyleMaskTitled
                                | NSWindowStyleMaskClosable
                                | NSWindowStyleMaskResizable
                                | NSWindowStyleMaskMiniaturizable;
        g_window = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
        [g_window setTitle:@"hexa term v1"];
        [g_window setBackgroundColor:[NSColor blackColor]];
        [g_window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
    return g_window ? 0 : -1;
}

// Pump the Cocoa event loop for `ms` milliseconds, dispatching any
// queued events. Non-blocking past the deadline — returns control
// to hexa so the caller can run its own logic and re-enter later.
long hexa_appkit_run_for_ms(long ms) {
    @autoreleasepool {
        NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:(double)ms / 1000.0];
        while ([deadline timeIntervalSinceNow] > 0) {
            NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:deadline
                                                inMode:NSDefaultRunLoopMode
                                               dequeue:YES];
            if (ev) {
                [NSApp sendEvent:ev];
            }
        }
    }
    return 0;
}

// Close the window cleanly. Paired with hexa_appkit_window_open_default.
long hexa_appkit_window_close(void) {
    @autoreleasepool {
        if (g_window) {
            [g_window close];
            g_window = nil;
        }
    }
    return 0;
}

// Probe — returns the screen's pixel dimensions packed as a long:
// (width << 32) | height. Gives hexa-side a way to observe the real
// display metrics without passing structs.
long hexa_appkit_screen_wh_packed(void) {
    @autoreleasepool {
        NSScreen* s = [NSScreen mainScreen];
        if (!s) return 0;
        NSRect r = [s frame];
        long w = (long)r.size.width;
        long h = (long)r.size.height;
        return (w << 32) | (h & 0xFFFFFFFF);
    }
}

// Attach a HexaDrawView as the current window's contentView. The view's
// frame matches the existing contentView bounds so the Core Text glyph
// render path can be exercised end-to-end. Precondition: caller must have
// successfully invoked hexa_appkit_window_open_default.
// Returns 0 on success, -1 if no window is currently open.
long hexa_appkit_attach_drawrect_view(void) {
    @autoreleasepool {
        if (!g_window) return -1;
        NSRect bounds = [[g_window contentView] bounds];
        HexaDrawView* drawView = [[HexaDrawView alloc] initWithFrame:bounds];
        [g_window setContentView:drawView];
        [drawView setNeedsDisplay:YES];
    }
    return 0;
}

// Pump the event loop briefly. If a keyDown event arrives, return the
// first character as a long (Unicode codepoint). Return 0 if no key
// event within the 50ms timeout. Used by the interactive event loop.
long hexa_appkit_next_key_char(void) {
    @autoreleasepool {
        NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskKeyDown
                                          untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                                             inMode:NSDefaultRunLoopMode
                                            dequeue:YES];
        if (ev) {
            NSString* chars = [ev characters];
            if ([chars length] > 0) {
                return (long)[chars characterAtIndex:0];
            }
        }
    }
    return 0;
}

// Make the HexaDrawView (contentView) the first responder so key
// events are delivered to it. Must be called after attach_drawrect_view.
long hexa_appkit_make_first_responder(void) {
    @autoreleasepool {
        if (g_window) {
            [g_window makeFirstResponder:[g_window contentView]];
        }
    }
    return 0;
}

// Set the current window's title — OSC 0 (set-window-title) precursor.
// Hardcoded test string so hexa extern fn can call it without pushing
// NSString payloads across the FFI boundary.
// Returns 0 on success.
long hexa_appkit_set_title(void) {
    @autoreleasepool {
        if (g_window) {
            [g_window setTitle:@"hexa term — OSC 0 title test"];
        }
    }
    return 0;
}

// ══════════════════════════════════════════════════════════════════
// void_main.hexa API — terminal bridge with tab support
// ══════════════════════════════════════════════════════════════════

#include <sys/wait.h>
#include <sys/ioctl.h>
#include <util.h>

#define TERM_MAX_ROWS 200
#define TERM_MAX_COLS 400
#define MAX_TABS 20
#define SCROLLBACK_LINES 1000 // legacy cap (unused since section-based)
#define TAB_BAR_W 140
#define TAB_ROW_H 28

// ── Section-based scrollback ──
// Old: flat 1000-line ring (6.4 MB allocated up front on first push).
// New: ring of SB_MAX_SECTIONS sections, each SB_SECTION_LINES lines.
//      Sections are lazy-allocated, and the oldest is freed when the ring
//      wraps — memory usage stays proportional to actual scrollback depth.
//      Totals: 32 × 64 = 2048 lines max, ~410 KB per section.
#define SB_SECTION_LINES 64
#define SB_MAX_SECTIONS  32
#define SB_TOTAL_LINES   (SB_SECTION_LINES * SB_MAX_SECTIONS)

typedef struct {
    unichar ch;
    int fg, bg, flags;
} TermCell;

typedef struct {
    TermCell *cells; // NULL until first write; SB_SECTION_LINES * TERM_MAX_COLS
    int lines;       // 0..SB_SECTION_LINES filled
} SbSection;

// Forward decl: needed by drawRect, defined after VoidTab.
struct VoidTab_;
static TermCell *sb_line_ptr(struct VoidTab_ *tab, int logical_line);
// Forward decl for alarm helpers used in HexaTermView (defined much later).
static void clear_active_alarm(void);
static void update_dock_badge(void);
static void poll_background_tabs(void);
// Forward decl for drag-reorder helper used in HexaTermView's mouseUp.
static void tabs_move(int from, int to);
// Forward decl for clipboard helpers used in HexaTermView's
// performKeyEquivalent fallback (defined further down next to
// hexa_appkit_term_flush).
static void copy_selection_to_clipboard(void);
static void paste_from_clipboard(void);
// Forward decls for the undo-close path used by performKeyEquivalent +
// hexa_appkit_term_poll Cmd intercept. Definitions live further down.
struct VoidProfile_; // forward decl of the struct tag
static void tab_reopen_last(void);
extern struct VoidProfile_ *g_pending_profile;
// Forward decl — defined after HexaTermView but read from tab_become_profile.
static int g_resized;

// ── Tab state ──
typedef struct VoidTab_ {
    int used;
    int pty_fd;
    pid_t pid;
    TermCell grid[TERM_MAX_ROWS][TERM_MAX_COLS];
    int cur_row, cur_col;
    char title[128];
    // Section-based scrollback (see comment above).
    SbSection sb[SB_MAX_SECTIONS];
    int sb_head;        // oldest live section index in ring
    int sb_num;         // count of live sections (0..SB_MAX_SECTIONS)
    int sb_total;       // total lines across all live sections
    // OSC 7 cwd (file://host/path) — updated by shell for autocomplete
    char cwd[1024];
    // Background activity indicator: set when the tab (while NOT active)
    // received any PTY output. Cleared when the tab is activated. Drives
    // the bell glyph in the tab bar and the Dock icon badge count.
    int has_alarm;
    // Profile-opened tabs lock the title so shell OSC 0 escape sequences
    // (which most prompts emit on every command) can't clobber the fixed
    // profile name like "nexus (1)".
    int title_locked;
    // Base profile name (e.g. "nexus") — empty if not opened from a profile.
    // Used to renumber sibling tabs when one is added or removed: a single
    // sibling stays bare ("nexus"), two or more become "nexus (1)", "nexus (2)".
    char profile_base[64];
    // Blank tab: no PTY spawned, no shell, no input/output. The initial tab
    // at app launch is blank so the user starts from a clean screen and
    // picks a profile via Cmd+Ctrl+N — the blank then converts in place
    // instead of creating a second tab. Cleared by tab_become_profile.
    int is_blank;
    // When the tab was spawned via the void-server daemon, this holds the
    // ULID-ish session id. Empty string = direct-spawn (server not used
    // for this tab). On Cmd+W, a non-empty id triggers a DETACH instead
    // of closing the PTY + killing the shell.
    char session_id[32];
    // Per-tab terminal dimensions for grid (tiling) layout mode. In stacked
    // mode all tabs share g_term_rows/g_term_cols; in grid mode each tile
    // gets its own rows/cols derived from its NSRect ÷ cell metrics, and
    // TIOCSWINSZ is sent to the PTY so the shell redraws at the right size.
    int tile_rows;
    int tile_cols;
    // Background-tab plain-text cursor in grid mode. Drained bytes from the
    // PTY are written cell-by-cell into the tab's own grid (bypassing the
    // hexa VT parser which has single global state). This is best-effort
    // v1 — full SGR/CSI escape sequences are stripped and only printable
    // ASCII + LF/CR/BS/TAB are rendered. The active tab still uses the
    // full hexa VT parser via the normal main loop read path.
    int bg_cur_row;
    int bg_cur_col;
    int bg_esc_state; // 0 = normal, 1 = saw ESC, 2 = inside CSI
} VoidTab;

static VoidTab g_tabs[MAX_TABS];
static int g_num_tabs = 0;
static int g_active_tab = -1;
static int g_tab_cmd = 0; // 0=none, 1=new, 2=close

// ── Layout mode (tiling grid vs stacked tab bar) ──
// Stacked: classic one-tab-at-a-time with the left tab bar (current default).
// Grid:    tiling mode where ALL live tabs render simultaneously, sized
//          automatically based on tab count (1=full, 2=1×2, 3=1×3, 4=2×2,
//          5-6=2×3, 7-9=3×3, 10+=falls back to stacked).
// Toggled by Cmd+G. When entering grid mode, per-tab tile_rows/tile_cols
// are recomputed and TIOCSWINSZ is sent to each PTY so shells redraw at
// their new sizes. When leaving grid mode, everyone goes back to sharing
// g_term_rows/g_term_cols.
typedef enum { LAYOUT_STACKED = 0, LAYOUT_GRID = 1 } LayoutMode;
static LayoutMode g_layout_mode = LAYOUT_STACKED;
// Invalidation flag — set when the layout mode or tab count changes so
// the main event loop reapplies tile rects on the next tick. Separate
// from g_resized so a plain Cmd+G toggle doesn't require a window resize
// to trigger a reflow.
static int g_layout_dirty = 0;

// Effective tab bar width — 0 when there is only one tab (matches
// Safari/Terminal.app: the chrome disappears so the user reclaims the pixels).
// Becomes TAB_BAR_W the moment a second tab is created, and collapses back
// when closed. A static cache of the last value drives the reflow check in
// the main event loop so window columns recompute exactly once per transition.
static int g_eff_tab_bar_w_cache = -1;
static inline int effective_tab_bar_w(void) {
    // Grid mode hides the tab bar entirely — tiles use the full bounds.
    // Falls back to the stacked bar when there are >9 tabs.
    if (g_layout_mode == LAYOUT_GRID && g_num_tabs >= 1 && g_num_tabs <= 9) return 0;
    return (g_num_tabs <= 1) ? 0 : TAB_BAR_W;
}

// Tab drag-and-drop reorder state. Set by mouseDown on the tab bar,
// read by mouseDragged / mouseUp / drawRect, cleared after the drop.
// g_drag_active turns on once the cursor has moved past a small threshold
// so a plain click still switches tabs without any visual churn.
static int g_drag_source = -1;
static int g_drag_target = -1;
static int g_drag_active = 0;
static NSPoint g_drag_origin;

// Recently-closed tab stack for Cmd+Z (undo-close). On close we push a
// snapshot of the tab's identity (title / profile base / cwd) so Cmd+Z
// can respawn a fresh tab of the same profile. The shell + scrollback
// are NOT restored — this is "reopen the profile I just closed" like
// Chrome's Cmd+Shift+T, not a full session snapshot.
#define CLOSED_STACK_MAX 16
typedef struct {
    char title[128];
    char profile_base[64];
    char cwd[1024];
    int  was_profile;     // 1 → push pending_profile on reopen
    int  original_idx;    // tab slot the closed tab lived at — reopen
                          // reinserts here via tabs_move after creation
} ClosedTabSnapshot;
static ClosedTabSnapshot g_closed_stack[CLOSED_STACK_MAX];
static int g_closed_count = 0;
// Deferred target slot for the next tab created via tab_reopen_last —
// set right before we flip g_tab_cmd=1; hexa_tab_new tails it back via
// tabs_move so the reopened tab lands exactly where it was closed.
static int g_reopen_target_idx = -1;

// ── Mouse text selection state ───────────────────────────────────────
// Set by mouseDown inside the grid area, extended by mouseDragged,
// finalized by mouseUp. drawRect shades every cell in the range with a
// translucent blue overlay BEFORE drawing the glyph. Cmd+C copies the
// text via NSPasteboard. ESC or any new keystroke clears the selection.
//
// Coordinates are in grid cells (row, col) anchored to g_term_grid —
// normalization (start <= end in row-major order) happens inline where
// it's needed so we can preserve the raw anchor if we ever want to
// stretch in either direction after the initial drag.
static int g_sel_start_row = -1, g_sel_start_col = -1;
static int g_sel_end_row = -1, g_sel_end_col = -1;
static int g_sel_active = 0;        // 1 once the user has dragged past the click origin
static int g_sel_anchor_in_grid = 0; // 1 if mouseDown landed inside the terminal grid
// Triple-click / double-click handling — NSEvent's clickCount already
// reports 2 for double, 3 for triple, but we need to know if a drag
// beyond the initial selection should override word/line mode.
static int g_sel_click_count = 0;

// Clear selection — used by ESC, keystrokes, scrollback transitions.
static inline void clear_selection(void) {
    if (g_sel_start_row < 0 && g_sel_end_row < 0) return;
    g_sel_start_row = g_sel_start_col = -1;
    g_sel_end_row = g_sel_end_col = -1;
    g_sel_active = 0;
    g_sel_anchor_in_grid = 0;
    g_sel_click_count = 0;
}

// Normalize a selection so (start_row, start_col) <= (end_row, end_col)
// in row-major order. Writes the normalized pair into *o_* output args.
// Returns 0 if the selection is empty / inactive.
static int normalize_selection(int *o_sr, int *o_sc, int *o_er, int *o_ec) {
    if (g_sel_start_row < 0 || g_sel_end_row < 0) return 0;
    int sr = g_sel_start_row, sc = g_sel_start_col;
    int er = g_sel_end_row,   ec = g_sel_end_col;
    if (sr > er || (sr == er && sc > ec)) {
        int tr = sr, tc = sc; sr = er; sc = ec; er = tr; ec = tc;
    }
    *o_sr = sr; *o_sc = sc; *o_er = er; *o_ec = ec;
    return 1;
}

// Forward-declare file-scope globals that the hot-swap serializer needs
// to touch. These are tentative definitions — the initialised version
// further down in the file merges with these under C's tentative-def rule.
static TermCell g_term_grid[TERM_MAX_ROWS][TERM_MAX_COLS];
static int g_term_rows;
static int g_term_cols;
static int g_term_cur_row;
static int g_term_cur_col;

// ── Speculative Hot Swap state ───────────────────────────────────────
// Self-replace across a rebuild while keeping PTY file descriptors (and
// therefore claude/shell subprocesses and their conversation history)
// alive across the exec. Flow:
//
//   parent void_term (PID N, old image)
//     ↓ SIGUSR1 from void-swap helper
//   g_want_swap = 1
//     ↓ main loop tick
//   save_handoff(/tmp/void_handoff_N.bin) — tab count, per-tab grid/title/fd/flags
//   clear FD_CLOEXEC on every g_tabs[i].pty_fd and on g_lock_fd
//   socketpair(sp) for RDY/GO signaling
//   fork() → child
//     child: execv(g_argv0, argv) with VOID_SHADOW=1, HANDOFF_PATH, HANDOFF_SOCK,
//            HANDOFF_LOCK_FD, HANDOFF_PID in env
//   parent: close child's end of sp, read "RDY\n"
//     parent orderOut window, write "GO\n", exit
//   child (new image): init_term sees VOID_SHADOW, restores state from handoff
//     file, creates hidden window, writes "RDY\n", waits for "GO\n", orderFronts
//
// PTY fds survive execv because fork() already duplicated them and we
// clear FD_CLOEXEC before exec. The child adopts the same integer fd
// numbers via the handoff file and resumes reading claude's output.
static int g_want_swap = 0;
static int g_shadow_restored = 0;   // 1 after successful VOID_SHADOW restore
static int g_shadow_sock = -1;       // our half of the RDY/GO socketpair
static char g_argv0[4096] = {0};     // captured at init for re-exec
// Signal handler can only set sig_atomic_t safely.
#include <signal.h>
static volatile sig_atomic_t g_swap_flag = 0;
static void handle_sigusr1(int sig) {
    (void)sig;
    g_swap_flag = 1;
}

// Handoff file format (packed, little-endian, same endian on a single
// machine so byte order not a concern). No versioning for v1 — the
// binary that reads is always the one that wrote the format (we rebuild
// both in one go). If the format changes, bump the magic below.
#define VOID_HANDOFF_MAGIC 0x564F4944u  // "VOID"
typedef struct {
    unsigned int magic;
    int          num_tabs;
    int          active_tab;
    int          term_rows;
    int          term_cols;
    // Window frame (points)
    double       win_x, win_y, win_w, win_h;
} HandoffHeader;

typedef struct {
    int          pty_fd;
    int          is_blank;
    int          title_locked;
    int          cur_row;
    int          cur_col;
    char         title[128];
    char         profile_base[64];
    char         cwd[1024];
    // Full live grid, fixed size so we can blit it straight into g_tabs[i].grid.
    TermCell     grid[TERM_MAX_ROWS][TERM_MAX_COLS];
} HandoffTab;

// Strip FD_CLOEXEC so fds survive execv into the shadow.
static void handoff_keep_fd(int fd) {
    if (fd < 0) return;
    int flags = fcntl(fd, F_GETFD, 0);
    if (flags < 0) return;
    fcntl(fd, F_SETFD, flags & ~FD_CLOEXEC);
}

// Capture whatever the shell-resolved executable path is, regardless of
// relative launch. Used as argv[0] for the child execv.
#include <mach-o/dyld.h>
static void capture_argv0_once(void) {
    if (g_argv0[0]) return;
    uint32_t bufsize = sizeof(g_argv0);
    if (_NSGetExecutablePath(g_argv0, &bufsize) != 0) {
        // buffer too small — unlikely, but fall back to a sensible default
        snprintf(g_argv0, sizeof(g_argv0),
                 "%s/Dev/void/void_term",
                 getenv("HOME") ?: "/Users/ghost");
    }
}

// Write the live tab state to a handoff file so a freshly-exec'd shadow
// process can read it back and resume. Must be called from the main
// loop (single-threaded, so g_tabs[] is stable). Returns 0 on success.
static int save_handoff_to_file(const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) return -1;

    // Save the ACTIVE tab's live grid into its own g_tabs entry first
    // — otherwise the most recent frame lives only in g_term_grid and
    // would be lost.
    if (g_active_tab >= 0 && g_active_tab < g_num_tabs) {
        memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
        g_tabs[g_active_tab].cur_row = g_term_cur_row;
        g_tabs[g_active_tab].cur_col = g_term_cur_col;
    }

    HandoffHeader h = {0};
    h.magic      = VOID_HANDOFF_MAGIC;
    h.num_tabs   = g_num_tabs;
    h.active_tab = g_active_tab;
    h.term_rows  = g_term_rows;
    h.term_cols  = g_term_cols;
    if (g_window) {
        NSRect fr = [g_window frame];
        h.win_x = fr.origin.x;
        h.win_y = fr.origin.y;
        h.win_w = fr.size.width;
        h.win_h = fr.size.height;
    }
    if (fwrite(&h, sizeof(h), 1, f) != 1) { fclose(f); return -1; }

    for (int i = 0; i < g_num_tabs; i++) {
        HandoffTab t = {0};
        t.pty_fd       = g_tabs[i].pty_fd;
        t.is_blank     = g_tabs[i].is_blank;
        t.title_locked = g_tabs[i].title_locked;
        t.cur_row      = g_tabs[i].cur_row;
        t.cur_col      = g_tabs[i].cur_col;
        memcpy(t.title,        g_tabs[i].title,        sizeof(t.title));
        memcpy(t.profile_base, g_tabs[i].profile_base, sizeof(t.profile_base));
        memcpy(t.cwd,          g_tabs[i].cwd,          sizeof(t.cwd));
        memcpy(t.grid,         g_tabs[i].grid,         sizeof(t.grid));
        if (fwrite(&t, sizeof(t), 1, f) != 1) { fclose(f); return -1; }
    }
    fclose(f);
    return 0;
}

// Restore tabs from a handoff file. Called from hexa_appkit_init_term
// when VOID_SHADOW is set. Returns 0 on success. The inherited pty_fd
// values are adopted verbatim — fork+exec guarantees they're still
// open in this process since we cleared FD_CLOEXEC before execv.
static int restore_handoff_from_file(const char *path, HandoffHeader *hout) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;

    HandoffHeader h;
    if (fread(&h, sizeof(h), 1, f) != 1 || h.magic != VOID_HANDOFF_MAGIC) {
        fclose(f);
        return -1;
    }
    if (h.num_tabs < 0 || h.num_tabs > MAX_TABS) { fclose(f); return -1; }

    for (int i = 0; i < h.num_tabs; i++) {
        HandoffTab t;
        if (fread(&t, sizeof(t), 1, f) != 1) { fclose(f); return -1; }
        memset(&g_tabs[i], 0, sizeof(VoidTab));
        g_tabs[i].used         = 1;
        g_tabs[i].pty_fd       = t.pty_fd;
        g_tabs[i].pid          = 0; // we don't track the child pid across swaps
        g_tabs[i].is_blank     = t.is_blank;
        g_tabs[i].title_locked = t.title_locked;
        g_tabs[i].cur_row      = t.cur_row;
        g_tabs[i].cur_col      = t.cur_col;
        memcpy(g_tabs[i].title,        t.title,        sizeof(t.title));
        memcpy(g_tabs[i].profile_base, t.profile_base, sizeof(t.profile_base));
        memcpy(g_tabs[i].cwd,          t.cwd,          sizeof(t.cwd));
        memcpy(g_tabs[i].grid,         t.grid,         sizeof(t.grid));
    }
    g_num_tabs   = h.num_tabs;
    g_active_tab = h.active_tab;
    g_term_rows  = h.term_rows;
    g_term_cols  = h.term_cols;
    if (g_active_tab >= 0 && g_active_tab < g_num_tabs)
        memcpy(g_term_grid, g_tabs[g_active_tab].grid, sizeof(g_term_grid));

    fclose(f);
    if (hout) *hout = h;
    g_shadow_restored = 1;
    return 0;
}

// Active tab's rendering grid (synced from hexa). g_term_grid +
// g_term_rows/cols/cur_row/cur_col are forward-declared above for the
// hot-swap serializer. C's tentative-definition rule merges those with
// the initialised definitions below into a single object each. The
// scalars need initial values (rows=24 cols=80) for the normal init
// path that runs before hexa_appkit_term_set_rows/cols fire.
static int g_term_rows_default __attribute__((unused)) = 24;
static int g_term_cols_default __attribute__((unused)) = 80;
static int g_term_cur_vis = 1;
static float g_term_cw = 0;
static float g_term_ch = 0;
static CTFontRef g_term_font = NULL;
static CTFontRef g_term_font_bold = NULL;
static int g_font_size = 13;       // current point size (Cmd+=/-/0 mutable)
static NSColor *g_term_color_cache[16] = {0}; // retained ANSI palette

// (Re)create the monospaced body font + bold variant at `sz` points, then
// recompute cell width/height from the M glyph advance. Used by init AND
// the Cmd+=/-/0 zoom handlers — the init path and the zoom path share the
// exact same SFMono → Menlo → Monaco fallback chain.
static void set_font_size(int sz) {
    if (sz < 8)  sz = 8;
    if (sz > 40) sz = 40;
    if (g_term_font)      { CFRelease(g_term_font);      g_term_font      = NULL; }
    if (g_term_font_bold) { CFRelease(g_term_font_bold); g_term_font_bold = NULL; }
    g_term_font = CTFontCreateWithName(CFSTR("SFMono-Regular"), sz, NULL);
    if (!g_term_font) g_term_font = CTFontCreateWithName(CFSTR("Menlo-Regular"), sz, NULL);
    if (!g_term_font) g_term_font = CTFontCreateWithName(CFSTR("Monaco"), sz, NULL);
    g_term_font_bold = CTFontCreateCopyWithSymbolicTraits(
        g_term_font, 0, NULL, kCTFontBoldTrait, kCTFontBoldTrait);
    if (!g_term_font_bold) g_term_font_bold = (CTFontRef)CFRetain(g_term_font);
    UniChar mc = 'M';
    CGGlyph gl;
    CTFontGetGlyphsForCharacters(g_term_font, &mc, &gl, 1);
    CGSize adv;
    CTFontGetAdvancesForGlyphs(g_term_font, kCTFontOrientationHorizontal, &gl, &adv, 1);
    g_term_cw = adv.width;
    g_term_ch = CTFontGetAscent(g_term_font) + CTFontGetDescent(g_term_font) +
                CTFontGetLeading(g_term_font) + 2;
    g_font_size = sz;
}

// ── Grid layout helpers ──
static void compute_grid_dims(int n, int *out_rows, int *out_cols) {
    int rows, cols;
    if      (n == 1) { rows = 1; cols = 1; }
    else if (n == 2) { rows = 1; cols = 2; }
    else if (n == 3) { rows = 1; cols = 3; }
    else if (n == 4) { rows = 2; cols = 2; }
    else if (n <= 6) { rows = 2; cols = 3; }
    else /* 7..9 */  { rows = 3; cols = 3; }
    *out_rows = rows;
    *out_cols = cols;
}

#define TILE_INSET 2

static NSRect compute_tile_rect(int idx, NSRect bounds, int n_tabs) {
    if (n_tabs <= 0 || idx < 0 || idx >= n_tabs) return NSZeroRect;
    int grid_rows, grid_cols;
    compute_grid_dims(n_tabs, &grid_rows, &grid_cols);
    int row = idx / grid_cols;
    int col = idx % grid_cols;
    float tile_w = bounds.size.width  / (float)grid_cols;
    float tile_h = bounds.size.height / (float)grid_rows;
    float x = col * tile_w;
    float y = row * tile_h;
    NSRect r = NSMakeRect(x + TILE_INSET, y + TILE_INSET,
                          tile_w - 2 * TILE_INSET, tile_h - 2 * TILE_INSET);
    if (r.size.width  < 0) r.size.width  = 0;
    if (r.size.height < 0) r.size.height = 0;
    return r;
}

static void apply_grid_layout(NSRect bounds) {
    if (g_num_tabs <= 0) return;
    if (g_term_cw <= 0 || g_term_ch <= 0) return;
    int use_grid = (g_layout_mode == LAYOUT_GRID && g_num_tabs >= 1 && g_num_tabs <= 9);
    for (int t = 0; t < g_num_tabs; t++) {
        if (!g_tabs[t].used) continue;
        int new_rows, new_cols;
        if (use_grid) {
            NSRect tile = compute_tile_rect(t, bounds, g_num_tabs);
            new_rows = (int)(tile.size.height / g_term_ch);
            new_cols = (int)(tile.size.width  / g_term_cw);
            if (new_rows < 3)  new_rows = 3;
            if (new_cols < 10) new_cols = 10;
        } else {
            new_rows = g_term_rows;
            new_cols = g_term_cols;
        }
        if (new_rows > TERM_MAX_ROWS) new_rows = TERM_MAX_ROWS;
        if (new_cols > TERM_MAX_COLS) new_cols = TERM_MAX_COLS;
        int changed = (g_tabs[t].tile_rows != new_rows ||
                       g_tabs[t].tile_cols != new_cols);
        g_tabs[t].tile_rows = new_rows;
        g_tabs[t].tile_cols = new_cols;
        if (g_tabs[t].bg_cur_row >= new_rows) g_tabs[t].bg_cur_row = new_rows - 1;
        if (g_tabs[t].bg_cur_col >= new_cols) g_tabs[t].bg_cur_col = new_cols - 1;
        if (changed && g_tabs[t].pty_fd >= 0) {
            struct winsize ws;
            ws.ws_row = (unsigned short)new_rows;
            ws.ws_col = (unsigned short)new_cols;
            ws.ws_xpixel = 0;
            ws.ws_ypixel = 0;
            ioctl(g_tabs[t].pty_fd, TIOCSWINSZ, &ws);
        }
    }
}

static int g_term_quit = 0;
static int g_scroll_offset = 0;    // 0 = live view, >0 = lines scrolled back
static int g_sb_push_col = 0;      // temp column index during row push

// ── Damage tracking (input-lag fix) ──
// set_cell/set_cursor mark dirty rows; flush translates them into a minimal
// setNeedsDisplayInRect call so drawRect's row loop culls untouched rows.
// Key press → PTY → parse → set_cell only dirties the affected rows, not
// the whole view, which caps redraw work at O(chars_changed) instead of
// O(ROWS × COLS) and prevents Core Text throughput from throttling input.
static int g_dirty_min = -1;
static int g_dirty_max = -1;
static int g_full_redraw = 1;      // force full redraw on next flush (tab switch, resize, init)
static int g_prev_cur_row = 0;
static int g_prev_cur_col = 0;

// Key ring buffer
#define TERM_KEY_SIZE 4096
static char g_term_keys[TERM_KEY_SIZE];
static int g_term_kr = 0;
static int g_term_kw = 0;

static void term_key_push(const char *data, int len) {
    for (int i = 0; i < len; i++) {
        g_term_keys[g_term_kw % TERM_KEY_SIZE] = data[i];
        g_term_kw++;
    }
}

// ── Cmd+F scrollback search ──
// State for the search overlay. Query is a UTF-8 byte buffer; matches hold
// normalized positions in "virtual scrollback" space where line indices
// 0..sb_total-1 refer to scrollback and sb_total..sb_total+rows-1 refer to
// the live grid. A match spans `len` cells starting at `(line, col)`.
#define SEARCH_QUERY_MAX   256
#define SEARCH_MATCH_MAX   4096

typedef struct {
    int line;   // virtual line index (scrollback + live)
    int col;    // column on that line
    int len;    // cell count (needle length after wide-cell collapse)
} SearchMatch;

static int          g_search_active = 0;
static char         g_search_query[SEARCH_QUERY_MAX] = {0};
static int          g_search_query_len = 0;
static int          g_search_cursor = 0;
static int          g_search_match_count = 0;
static SearchMatch  g_search_matches[SEARCH_MATCH_MAX];

static inline int search_tolower_ascii(int c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    return c;
}

// Fetch a row of cells from the virtual scrollback space:
//   line in [0, sb_total)           → scrollback line via sb_line_ptr
//   line in [sb_total, sb_total+rows] → live g_term_grid row (line - sb_total)
// Returns NULL if out of range.
static TermCell *search_row_ptr(VoidTab *tab, int line) {
    if (!tab) return NULL;
    int sbn = tab->sb_total;
    if (line < 0) return NULL;
    if (line < sbn) return sb_line_ptr((struct VoidTab_ *)tab, line);
    int r = line - sbn;
    if (r >= 0 && r < g_term_rows && r < TERM_MAX_ROWS) return g_term_grid[r];
    return NULL;
}

// Return the effective column count for a given row, trimmed so trailing
// spaces aren't matched (so queries like "fail" match `fail<EOL>` without
// needing to account for the row's padding).
static int search_row_effective_cols(TermCell *row) {
    if (!row) return 0;
    int last = -1;
    for (int c = 0; c < g_term_cols; c++) {
        unichar ch = row[c].ch;
        if (ch > ' ') last = c;
    }
    return last + 1;
}

// Linear scan over scrollback + live grid. ASCII-insensitive substring
// match, wide-char continuation slots skipped when stepping through cells.
// Populates g_search_matches[] up to SEARCH_MATCH_MAX. Clamps cursor.
static void search_rescan(void) {
    g_search_match_count = 0;
    if (g_search_query_len <= 0) {
        g_search_cursor = 0;
        return;
    }
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return;
    VoidTab *tab = &g_tabs[g_active_tab];

    int total_lines = tab->sb_total + g_term_rows;
    int qlen = g_search_query_len;
    // Lowercased needle, reused per haystack row.
    char needle[SEARCH_QUERY_MAX];
    for (int i = 0; i < qlen; i++)
        needle[i] = (char)search_tolower_ascii((unsigned char)g_search_query[i]);

    for (int line = 0; line < total_lines; line++) {
        TermCell *row = search_row_ptr(tab, line);
        if (!row) continue;
        int ncols = search_row_effective_cols(row);
        if (ncols < qlen) continue;
        for (int c = 0; c + qlen <= ncols; c++) {
            // Skip wide-char continuation slots as start positions.
            if (row[c].flags & 0x20000) continue;
            int k = 0;
            int cc = c;
            while (k < qlen && cc < ncols) {
                // Skip continuation slot mid-comparison.
                if (row[cc].flags & 0x20000) { cc++; continue; }
                unichar uch = row[cc].ch;
                int lch = search_tolower_ascii((int)uch);
                if (lch != (unsigned char)needle[k]) break;
                k++;
                cc++;
            }
            if (k == qlen) {
                if (g_search_match_count < SEARCH_MATCH_MAX) {
                    g_search_matches[g_search_match_count].line = line;
                    g_search_matches[g_search_match_count].col  = c;
                    g_search_matches[g_search_match_count].len  = cc - c;
                    g_search_match_count++;
                }
                // Advance past this match so overlapping starts don't
                // bloat the list; matches how "Find" in most editors
                // reports non-overlapping hits.
                c = cc - 1;
            }
        }
        if (g_search_match_count >= SEARCH_MATCH_MAX) break;
    }
    if (g_search_match_count == 0) {
        g_search_cursor = 0;
    } else if (g_search_cursor >= g_search_match_count) {
        g_search_cursor = g_search_match_count - 1;
    }
}

// After cursor move, set g_scroll_offset so the current match sits roughly
// in the middle of the terminal grid. Scrollback offset is measured in
// "lines from the top of scrollback that are visible" — the drawRect path
// maps vline = sb_total - g_scroll_offset + row, so the top row of the
// view is virtual line (sb_total - g_scroll_offset).
static void search_center_current(void) {
    if (g_search_match_count <= 0) return;
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return;
    VoidTab *tab = &g_tabs[g_active_tab];
    int sbn = tab->sb_total;
    int line = g_search_matches[g_search_cursor].line;
    // Desired: put `line` at row (g_term_rows/2) in the viewport.
    int top_line = line - g_term_rows / 2;
    if (top_line < 0) top_line = 0;
    // offset = sbn - top_line  (only meaningful in scrollback region)
    int offset = sbn - top_line;
    // If the match is in the live area and fully visible without scrolling,
    // pin offset to 0 so the user sees the live view.
    if (line >= sbn && top_line >= sbn) {
        offset = 0;
    }
    if (offset < 0) offset = 0;
    int max_sb = sbn;
    if (offset > max_sb) offset = max_sb;
    g_scroll_offset = offset;
    g_full_redraw = 1;
}

// Append UTF-8 bytes to the query buffer, cap at SEARCH_QUERY_MAX-1.
static void search_append_bytes(const char *bytes, int n) {
    if (n <= 0) return;
    if (g_search_query_len + n >= SEARCH_QUERY_MAX) {
        n = SEARCH_QUERY_MAX - 1 - g_search_query_len;
        if (n <= 0) return;
    }
    memcpy(g_search_query + g_search_query_len, bytes, n);
    g_search_query_len += n;
    g_search_query[g_search_query_len] = 0;
    search_rescan();
    search_center_current();
}

// Pop the last codepoint from the query buffer. Drops trailing UTF-8
// continuation bytes (0x80..0xBF) together with their lead byte so a
// single Backspace removes a whole character instead of a fragment.
static void search_backspace(void) {
    if (g_search_query_len <= 0) return;
    g_search_query_len--;
    while (g_search_query_len > 0 &&
           (unsigned char)g_search_query[g_search_query_len] >= 0x80 &&
           (unsigned char)g_search_query[g_search_query_len] <  0xC0) {
        g_search_query_len--;
    }
    g_search_query[g_search_query_len] = 0;
    search_rescan();
    search_center_current();
}

static void search_next(void) {
    if (g_search_match_count <= 0) return;
    g_search_cursor = (g_search_cursor + 1) % g_search_match_count;
    search_center_current();
}

static void search_prev(void) {
    if (g_search_match_count <= 0) return;
    g_search_cursor = (g_search_cursor - 1 + g_search_match_count) % g_search_match_count;
    search_center_current();
}

static void search_open(void) {
    g_search_active = 1;
    g_search_query_len = 0;
    g_search_query[0] = 0;
    g_search_cursor = 0;
    g_search_match_count = 0;
    g_full_redraw = 1;
}

static void search_close(void) {
    g_search_active = 0;
    g_search_query_len = 0;
    g_search_query[0] = 0;
    g_search_cursor = 0;
    g_search_match_count = 0;
    // Leave g_scroll_offset untouched so the user can keep viewing the
    // match they landed on; a subsequent PTY-bound keystroke will snap
    // back to the live view via the existing keyDown reset.
    g_full_redraw = 1;
}

// ANSI color
static NSColor *term_color(int idx) {
    // Terminal.app Basic dark palette
    static const uint32_t a16[] = {
        0x000000,0xC33720,0x00BC12,0xC7BC09,
        0x0037DA,0xBB3FC6,0x00BBBB,0xBFBFBF,
        0x686868,0xED4E39,0x2DE636,0xD9D326,
        0x2B78E4,0xD256DE,0x33D7D7,0xE5E5E5
    };
    if (idx < 0) idx = 7;
    if (idx < 16) {
        // Cache hot path: 16 ANSI colors are retained at first access,
        // never released. Avoids ~3840 NSColor allocs per drawRect.
        if (!g_term_color_cache[idx]) {
            uint32_t c = a16[idx];
            g_term_color_cache[idx] = [[NSColor colorWithRed:((c>>16)&0xFF)/255.0
                                                       green:((c>>8)&0xFF)/255.0
                                                        blue:(c&0xFF)/255.0
                                                       alpha:1.0] retain];
        }
        return g_term_color_cache[idx];
    }
    if (idx < 232) {
        int v = idx - 16;
        int r = v/36, g = (v%36)/6, b = v%6;
        return [NSColor colorWithRed:r?(r*40+55)/255.0:0
                               green:g?(g*40+55)/255.0:0
                                blue:b?(b*40+55)/255.0:0 alpha:1.0];
    }
    if (idx < 256) {
        int g = (idx-232)*10+8;
        return [NSColor colorWithRed:g/255.0 green:g/255.0 blue:g/255.0 alpha:1.0];
    }
    int rgb = idx - 256;
    return [NSColor colorWithRed:(rgb/65536)/255.0
                           green:((rgb%65536)/256)/255.0
                            blue:(rgb%256)/255.0 alpha:1.0];
}

// ── HexaTermView (with tab bar) ──

@interface HexaTermView : NSView
@end

@implementation HexaTermView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    if (!g_term_font) return;
    // Wrap entire draw in pool — drains transient autoreleased objects
    // (NSString, NSAttributedString, NSDictionary) per frame instead of
    // letting them accumulate in the outer event-loop pool.
    @autoreleasepool {
    NSRect bounds = [self bounds];

    // ── Grid (tiling) layout path ──
    // When Cmd+G has put us in grid mode AND the tab count is within the
    // supported range (1-9), render every tab simultaneously. 10+ tabs
    // falls back to the stacked path below via effective_tab_bar_w().
    if (g_layout_mode == LAYOUT_GRID && g_num_tabs >= 1 && g_num_tabs <= 9) {
        // Paint the whole canvas black so tile gutters (the 2px inset)
        // read as a distinct separator instead of showing bare bounds.
        [[NSColor blackColor] setFill];
        NSRectFill(bounds);

        NSMutableDictionary *attrBuf = [NSMutableDictionary dictionaryWithCapacity:3];
        NSNumber *underlineNum = @(NSUnderlineStyleSingle);

        for (int t = 0; t < g_num_tabs; t++) {
            if (!g_tabs[t].used) continue;
            NSRect tile = compute_tile_rect(t, bounds, g_num_tabs);
            if (tile.size.width <= 0 || tile.size.height <= 0) continue;

            // Tile background
            [[NSColor blackColor] setFill];
            NSRectFill(tile);

            int tile_rows = g_tabs[t].tile_rows > 0 ? g_tabs[t].tile_rows : g_term_rows;
            int tile_cols = g_tabs[t].tile_cols > 0 ? g_tabs[t].tile_cols : g_term_cols;
            if (tile_rows > TERM_MAX_ROWS) tile_rows = TERM_MAX_ROWS;
            if (tile_cols > TERM_MAX_COLS) tile_cols = TERM_MAX_COLS;

            // Cell source: the ACTIVE tab's live frame lives in g_term_grid
            // (hexa's parser writes there). Background tabs read from
            // their own g_tabs[t].grid (populated by bg_tab_write_bytes
            // in poll_background_tabs). This keeps the active tab's hexa
            // VT pipeline untouched.
            TermCell (*src_grid)[TERM_MAX_COLS] =
                (t == g_active_tab) ? g_term_grid : g_tabs[t].grid;

            float ox = tile.origin.x;
            float oy = tile.origin.y;
            float max_x = tile.origin.x + tile.size.width;
            float max_y = tile.origin.y + tile.size.height;
            for (int r = 0; r < tile_rows; r++) {
                float y = oy + r * g_term_ch;
                if (y >= max_y) break;
                if (y + g_term_ch < dirtyRect.origin.y ||
                    y > dirtyRect.origin.y + dirtyRect.size.height) continue;
                TermCell *cell_row = src_grid[r];
                for (int c = 0; c < tile_cols; c++) {
                    float x = ox + c * g_term_cw;
                    if (x + g_term_cw > max_x) break;
                    TermCell *cell = &cell_row[c];
                    if (cell->flags & 0x20000) continue;
                    int wide = (cell->flags & 0x10000) != 0;
                    float cell_w = wide ? (2.0f * g_term_cw) : g_term_cw;
                    int bg = cell->bg, fg = cell->fg;
                    if (cell->flags & 8) { int tt = bg; bg = fg; fg = tt; }
                    if (bg != 0) {
                        [term_color(bg) setFill];
                        NSRectFill(NSMakeRect(x, y, cell_w, g_term_ch));
                    }
                    if (cell->ch <= ' ') continue;

                    CTFontRef df = (cell->flags & 1) ? g_term_font_bold : g_term_font;
                    [attrBuf removeAllObjects];
                    attrBuf[NSFontAttributeName] = (__bridge id)df;
                    attrBuf[NSForegroundColorAttributeName] = term_color(fg);
                    if (cell->flags & 4) attrBuf[NSUnderlineStyleAttributeName] = underlineNum;
                    unichar uch = cell->ch;
                    NSString *s = [NSString stringWithCharacters:&uch length:1];
                    NSAttributedString *as = [[NSAttributedString alloc] initWithString:s attributes:attrBuf];
                    [as drawAtPoint:NSMakePoint(x, y + 2)];
                    [as release];
                }
            }

            // Tile border: 2px highlight for the active tab, thin 1px
            // dim frame for the others. Drawn as 4 NSRectFill edges so
            // we avoid the cost of NSBezierPath for a simple rectangle.
            NSColor *border = (t == g_active_tab)
                ? [NSColor colorWithRed:0.4 green:0.6 blue:1.0 alpha:0.8]
                : [NSColor colorWithWhite:0.2 alpha:1.0];
            float bw = (t == g_active_tab) ? 2.0f : 1.0f;
            [border setFill];
            NSRectFill(NSMakeRect(tile.origin.x, tile.origin.y, tile.size.width, bw));
            NSRectFill(NSMakeRect(tile.origin.x,
                                  tile.origin.y + tile.size.height - bw,
                                  tile.size.width, bw));
            NSRectFill(NSMakeRect(tile.origin.x, tile.origin.y, bw, tile.size.height));
            NSRectFill(NSMakeRect(tile.origin.x + tile.size.width - bw,
                                  tile.origin.y, bw, tile.size.height));

            // Title strip near the top-left of each tile (small label so
            // the user can tell tabs apart when they share a prompt).
            if (g_tabs[t].title[0]) {
                NSDictionary *ta = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:10],
                    NSForegroundColorAttributeName:
                        (t == g_active_tab)
                          ? [NSColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:0.95]
                          : [NSColor colorWithRed:0.55 green:0.55 blue:0.55 alpha:0.95]
                };
                NSString *tn = [NSString stringWithUTF8String:g_tabs[t].title];
                [tn drawAtPoint:NSMakePoint(tile.origin.x + 6, tile.origin.y + 3)
                 withAttributes:ta];
            }

            // Active tab's cursor: only the active tile owns a visible
            // cursor. We use the active rendering cursor position from
            // g_term_cur_row/col.
            if (t == g_active_tab && g_term_cur_vis &&
                g_term_cur_row < tile_rows && g_term_cur_col < tile_cols) {
                [[NSColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:0.5] setFill];
                NSRectFill(NSMakeRect(ox + g_term_cur_col * g_term_cw,
                                      oy + g_term_cur_row * g_term_ch,
                                      g_term_cw, g_term_ch));
            }
        }
        // Grid path exits through the outer @autoreleasepool as the
        // method returns — pool drains automatically.
        return;
    }

    // ── Stacked (classic) layout path ──
    // ── Tab bar (left panel) ── skipped entirely when there is only one
    // tab, so the terminal grid reclaims the full width.
    int eff_tbw = effective_tab_bar_w();
    if (eff_tbw > 0) {
        [[NSColor colorWithRed:0.11 green:0.11 blue:0.11 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, eff_tbw, bounds.size.height));

        // Separator line
        [[NSColor colorWithRed:0.20 green:0.20 blue:0.20 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(eff_tbw - 1, 0, 1, bounds.size.height));

        NSFont *tabFont = [NSFont systemFontOfSize:11];
        for (int t = 0; t < g_num_tabs; t++) {
            float ty = 4 + t * TAB_ROW_H;
            // Active tab highlight
            if (t == g_active_tab) {
                [[NSColor colorWithRed:0.18 green:0.18 blue:0.18 alpha:1.0] setFill];
                NSRectFill(NSMakeRect(0, ty, eff_tbw - 1, TAB_ROW_H));
                // Accent bar
                [[NSColor colorWithRed:0.40 green:0.40 blue:0.40 alpha:1.0] setFill];
                NSRectFill(NSMakeRect(0, ty, 3, TAB_ROW_H));
            }

            // Tab title
            NSString *title;
            if (g_tabs[t].title[0])
                title = [NSString stringWithUTF8String:g_tabs[t].title];
            else
                title = [NSString stringWithFormat:@"Tab %d", t + 1];

            NSDictionary *attrs = @{
                NSFontAttributeName: tabFont,
                NSForegroundColorAttributeName:
                    (t == g_active_tab)
                        ? [NSColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]
                        : [NSColor colorWithRed:0.45 green:0.45 blue:0.45 alpha:1.0]
            };
            [title drawAtPoint:NSMakePoint(10, ty + 6) withAttributes:attrs];

            // Activity bell: matches Terminal.app's inactive-tab indicator.
            // Shown when a background tab received output since the user last
            // looked at it. Cleared on activation via clear_active_alarm().
            if (g_tabs[t].has_alarm && t != g_active_tab) {
                NSDictionary *bellAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:11],
                    NSForegroundColorAttributeName:
                        [NSColor colorWithRed:1.0 green:0.55 blue:0.15 alpha:1.0]
                };
                // U+1F514 is too heavy; U+2022 bullet or "●" works cleaner.
                // Use a simple filled dot to stay legible at 11pt.
                [@"\u25CF" drawAtPoint:NSMakePoint(eff_tbw - 18, ty + 6)
                        withAttributes:bellAttrs];
            }
        }

        // Drag-reorder feedback: highlight the drop slot while the user
        // is dragging so the impending new position is obvious.
        if (g_drag_active && g_drag_target >= 0 && g_drag_target < g_num_tabs) {
            float ty = 4 + g_drag_target * TAB_ROW_H;
            [[NSColor colorWithRed:0.40 green:0.60 blue:1.00 alpha:0.22] setFill];
            NSRectFill(NSMakeRect(0, ty, eff_tbw - 1, TAB_ROW_H));
            // Thin top bar so the insertion line is clearly readable.
            [[NSColor colorWithRed:0.40 green:0.60 blue:1.00 alpha:0.85] setFill];
            NSRectFill(NSMakeRect(0, ty, eff_tbw - 1, 2));
        }
    }

    // ── Terminal grid (right of tab bar, or full width when tab bar hidden) ──
    float ox = eff_tbw;
    [[NSColor blackColor] setFill];
    NSRectFill(NSMakeRect(ox, 0, bounds.size.width - ox, bounds.size.height));

    VoidTab *atab = (g_active_tab >= 0 && g_active_tab < g_num_tabs) ? &g_tabs[g_active_tab] : NULL;

    // Reusable mutable attribute dict — built once, mutated per cell.
    // Avoids 1920+ NSMutableDictionary allocs per frame.
    NSMutableDictionary *attrBuf = [NSMutableDictionary dictionaryWithCapacity:3];
    NSNumber *underlineNum = @(NSUnderlineStyleSingle);

    for (int r = 0; r < g_term_rows; r++) {
        float y = r * g_term_ch;
        if (y + g_term_ch < dirtyRect.origin.y ||
            y > dirtyRect.origin.y + dirtyRect.size.height) continue;

        // Determine cell source: scrollback section or live grid
        TermCell *cell_row = NULL;
        if (g_scroll_offset > 0 && atab) {
            int sb_n = atab->sb_total;
            int vline = sb_n - g_scroll_offset + r;
            if (vline >= 0 && vline < sb_n) {
                cell_row = sb_line_ptr(atab, vline);
            } else if (vline >= sb_n) {
                int sr = vline - sb_n;
                if (sr >= 0 && sr < TERM_MAX_ROWS) cell_row = g_term_grid[sr];
            }
        } else {
            cell_row = g_term_grid[r];
        }
        if (!cell_row) continue;

        for (int c = 0; c < g_term_cols; c++) {
            float x = ox + c * g_term_cw;
            TermCell *cell = &cell_row[c];
            // Continuation cell for a wide char drawn at (c-1) — the
            // glyph itself already covers this cell; just skip it. Its
            // background is part of the wide cell's double-fill so we
            // don't need to re-fill here either.
            if (cell->flags & 0x20000) continue;
            int wide = (cell->flags & 0x10000) != 0;
            float cell_w = wide ? (2.0f * g_term_cw) : g_term_cw;
            int bg = cell->bg, fg = cell->fg;
            if (cell->flags & 8) { int t = bg; bg = fg; fg = t; }
            if (bg != 0) {
                [term_color(bg) setFill];
                NSRectFill(NSMakeRect(x, y, cell_w, g_term_ch));
            }
            if (cell->ch <= ' ') continue;

            // Use cached fonts and cached colors — no per-cell CFCreate.
            CTFontRef df = (cell->flags & 1) ? g_term_font_bold : g_term_font;
            [attrBuf removeAllObjects];
            // CTFont is toll-free bridged to NSFont — NSFontAttributeName accepts it
            attrBuf[NSFontAttributeName] = (__bridge id)df;
            // NSForegroundColorAttributeName takes NSColor — no CGColor
            // bridging hazard. term_color() returns a retained cached object.
            attrBuf[NSForegroundColorAttributeName] = term_color(fg);
            if (cell->flags & 4) attrBuf[NSUnderlineStyleAttributeName] = underlineNum;

            unichar uch = cell->ch;
            NSString *s = [NSString stringWithCharacters:&uch length:1];
            NSAttributedString *as = [[NSAttributedString alloc] initWithString:s attributes:attrBuf];
            [as drawAtPoint:NSMakePoint(x, y + 2)];
            [as release]; // MRR — was leaking ~1920 objs/frame
        }
    }
    // ── Selection overlay ── translucent blue shade painted ON TOP of the
    // glyph layer so both background and foreground remain visible through
    // the highlight. Only active in live view (no scrollback) — dragging
    // into scrollback is a future milestone.
    if (g_scroll_offset == 0) {
        int ssr, ssc, ser, sec;
        if (normalize_selection(&ssr, &ssc, &ser, &sec)) {
            [[NSColor colorWithRed:0.2 green:0.35 blue:0.6 alpha:0.5] setFill];
            for (int r = ssr; r <= ser && r < g_term_rows; r++) {
                int c0 = (r == ssr) ? ssc : 0;
                int c1 = (r == ser) ? sec : (g_term_cols - 1);
                if (c0 < 0) c0 = 0;
                if (c1 >= g_term_cols) c1 = g_term_cols - 1;
                if (c0 > c1) continue;
                float rx = ox + c0 * g_term_cw;
                float ry = r * g_term_ch;
                float rw = (c1 - c0 + 1) * g_term_cw;
                NSRectFillUsingOperation(NSMakeRect(rx, ry, rw, g_term_ch),
                                         NSCompositingOperationSourceOver);
            }
        }
    }
    // Cursor — only visible in live view
    if (g_scroll_offset == 0 && g_term_cur_vis &&
        g_term_cur_row < g_term_rows && g_term_cur_col < g_term_cols) {
        [[NSColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:0.5] setFill];
        NSRectFill(NSMakeRect(ox + g_term_cur_col * g_term_cw,
                              g_term_cur_row * g_term_ch, g_term_cw, g_term_ch));
    }
    // Scrollback indicator
    if (g_scroll_offset > 0) {
        NSString *ind = [NSString stringWithFormat:@"[%d/%d]",
                         g_scroll_offset, atab ? atab->sb_total : 0];
        NSDictionary *ia = @{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName:
                [NSColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:0.7]
        };
        NSSize isz = [ind sizeWithAttributes:ia];
        [ind drawAtPoint:NSMakePoint(bounds.size.width - isz.width - 6, 4) withAttributes:ia];
    }

    // ── Cmd+F search overlay ──
    // Layered on top of the existing grid/scrollback render: highlight
    // every visible match with a translucent yellow rect, the current
    // match with a brighter orange rect, then draw a bottom status bar
    // with the query text and match counter. Does not touch the cell
    // render path so the base drawing stays unchanged.
    if (g_search_active && atab) {
        int sbn = atab->sb_total;
        int view_top_vline = (g_scroll_offset > 0) ? (sbn - g_scroll_offset) : sbn;
        int view_bot_vline = view_top_vline + g_term_rows;
        NSColor *hitAll = [NSColor colorWithRed:0.9 green:0.8 blue:0.1 alpha:0.4];
        NSColor *hitCur = [NSColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:0.7];
        for (int m = 0; m < g_search_match_count; m++) {
            SearchMatch *sm = &g_search_matches[m];
            if (sm->line < view_top_vline || sm->line >= view_bot_vline) continue;
            int row = sm->line - view_top_vline;
            float x = ox + sm->col * g_term_cw;
            float y = row * g_term_ch;
            float w = sm->len * g_term_cw;
            if (m == g_search_cursor) [hitCur setFill];
            else                       [hitAll setFill];
            NSRectFill(NSMakeRect(x, y, w, g_term_ch));
        }
        // Bottom status bar: 2 rows tall, dark translucent, with query
        // text on the left and "N/M" counter on the right.
        float bar_h = g_term_ch * 2;
        if (bar_h < 28) bar_h = 28;
        float bar_y = bounds.size.height - bar_h;
        [[NSColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.88] setFill];
        NSRectFill(NSMakeRect(ox, bar_y, bounds.size.width - ox, bar_h));
        // Top border line so the bar reads as a distinct UI chrome strip.
        [[NSColor colorWithRed:0.35 green:0.35 blue:0.35 alpha:0.8] setFill];
        NSRectFill(NSMakeRect(ox, bar_y, bounds.size.width - ox, 1));

        NSFont *bf = [NSFont systemFontOfSize:12];
        NSDictionary *qa = @{
            NSFontAttributeName: bf,
            NSForegroundColorAttributeName:
                [NSColor colorWithRed:0.95 green:0.95 blue:0.95 alpha:1.0]
        };
        NSDictionary *la = @{
            NSFontAttributeName: bf,
            NSForegroundColorAttributeName:
                [NSColor colorWithRed:0.6 green:0.75 blue:0.95 alpha:1.0]
        };
        NSDictionary *ca = @{
            NSFontAttributeName: bf,
            NSForegroundColorAttributeName:
                (g_search_match_count > 0
                     ? [NSColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]
                     : [NSColor colorWithRed:0.95 green:0.4 blue:0.3 alpha:1.0])
        };
        NSString *label = @"Find: ";
        NSString *query = g_search_query_len > 0
            ? [[[NSString alloc] initWithBytes:g_search_query
                                        length:g_search_query_len
                                      encoding:NSUTF8StringEncoding] autorelease]
            : @"";
        if (!query) query = @"";
        NSString *counter = g_search_match_count > 0
            ? [NSString stringWithFormat:@"%d/%d",
                        g_search_cursor + 1, g_search_match_count]
            : (g_search_query_len > 0 ? @"no match" : @"");

        float tx = ox + 10;
        float ty = bar_y + (bar_h - 14) / 2;
        NSSize lsz = [label sizeWithAttributes:la];
        [label drawAtPoint:NSMakePoint(tx, ty) withAttributes:la];
        tx += lsz.width;
        [query drawAtPoint:NSMakePoint(tx, ty) withAttributes:qa];
        // Blinking-ish caret after the query: thin vertical bar so the
        // user sees they can still type.
        NSSize qsz = [query sizeWithAttributes:qa];
        [[NSColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:0.7] setFill];
        NSRectFill(NSMakeRect(tx + qsz.width + 1, ty + 1, 2, 14));

        NSSize csz = [counter sizeWithAttributes:ca];
        [counter drawAtPoint:NSMakePoint(bounds.size.width - csz.width - 10, ty)
              withAttributes:ca];
    }

    // ── Floating toolbar (bottom-right) ──
    // Two always-visible buttons:
    //   [▦] grid-mode toggle (equivalent to Cmd+G)
    //   [⟳] cycle to next tab
    // Placed at bottom-right so they're reachable even when the tab bar
    // is hidden (1 tab) or the user is in grid mode. Mouse hit-tests
    // against the same rects in mouseDown.
    {
        const float BTN_W = 28, BTN_H = 28, BTN_PAD = 8, BTN_GAP = 4;
        float by = bounds.size.height - BTN_H - BTN_PAD;
        float bx_cycle = bounds.size.width - BTN_W - BTN_PAD;
        float bx_grid  = bx_cycle - BTN_W - BTN_GAP;
        NSRect r_grid  = NSMakeRect(bx_grid,  by, BTN_W, BTN_H);
        NSRect r_cycle = NSMakeRect(bx_cycle, by, BTN_W, BTN_H);

        // Background plate — semi-transparent so terminal content
        // underneath is still partially visible.
        NSColor *plate = [NSColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:0.85];
        NSColor *border = [NSColor colorWithRed:0.30 green:0.30 blue:0.35 alpha:0.9];
        NSColor *ink = [NSColor colorWithWhite:0.85 alpha:1.0];
        NSColor *ink_active = [NSColor colorWithRed:0.4 green:0.65 blue:1.0 alpha:1.0];

        for (int i = 0; i < 2; i++) {
            NSRect r = i == 0 ? r_grid : r_cycle;
            NSBezierPath *bp = [NSBezierPath bezierPathWithRoundedRect:r xRadius:5 yRadius:5];
            [plate setFill];
            [bp fill];
            [border setStroke];
            [bp setLineWidth:1.0];
            [bp stroke];
        }

        // Grid icon — 2x2 squares
        {
            int active = (g_layout_mode == LAYOUT_GRID);
            NSColor *c = active ? ink_active : ink;
            [c setFill];
            float cx = r_grid.origin.x + 6;
            float cy = r_grid.origin.y + 6;
            NSRectFill(NSMakeRect(cx,       cy,       6, 6));
            NSRectFill(NSMakeRect(cx + 8,   cy,       6, 6));
            NSRectFill(NSMakeRect(cx,       cy + 8,   6, 6));
            NSRectFill(NSMakeRect(cx + 8,   cy + 8,   6, 6));
        }

        // Cycle icon — right-pointing chevron
        {
            [ink setStroke];
            NSBezierPath *chev = [NSBezierPath bezierPath];
            float cx = r_cycle.origin.x + BTN_W / 2;
            float cy = r_cycle.origin.y + BTN_H / 2;
            [chev moveToPoint:NSMakePoint(cx - 5, cy - 6)];
            [chev lineToPoint:NSMakePoint(cx + 4, cy)];
            [chev lineToPoint:NSMakePoint(cx - 5, cy + 6)];
            [chev setLineWidth:2.0];
            [chev setLineCapStyle:NSLineCapStyleRound];
            [chev setLineJoinStyle:NSLineJoinStyleRound];
            [chev stroke];
        }
    }
    } // @autoreleasepool
}

// Toolbar button hit-test — shared by mouseDown. Returns 1 if (p) is
// on the grid toggle, 2 if on the cycle button, 0 otherwise.
static int toolbar_button_at(NSPoint p, NSRect bounds) {
    const float BTN_W = 28, BTN_H = 28, BTN_PAD = 8, BTN_GAP = 4;
    float by = bounds.size.height - BTN_H - BTN_PAD;
    float bx_cycle = bounds.size.width - BTN_W - BTN_PAD;
    float bx_grid  = bx_cycle - BTN_W - BTN_GAP;
    NSRect r_grid  = NSMakeRect(bx_grid,  by, BTN_W, BTN_H);
    NSRect r_cycle = NSMakeRect(bx_cycle, by, BTN_W, BTN_H);
    if (NSPointInRect(p, r_grid))  return 1;
    if (NSPointInRect(p, r_cycle)) return 2;
    return 0;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect selfBounds = [self bounds];

    // Floating toolbar hit-test first — these rects live above every
    // other region so they work in both stacked and grid modes and
    // regardless of tab count.
    int btn = toolbar_button_at(p, selfBounds);
    if (btn == 1) {
        // Grid toggle — same behavior as Cmd+G.
        if (g_num_tabs >= 1 && g_num_tabs <= 9)
            g_layout_mode = (g_layout_mode == LAYOUT_GRID)
                ? LAYOUT_STACKED : LAYOUT_GRID;
        else
            g_layout_mode = LAYOUT_STACKED;
        g_layout_dirty = 1;
        g_full_redraw = 1;
        g_eff_tab_bar_w_cache = -1;
        [[NSUserDefaults standardUserDefaults]
            setInteger:(NSInteger)g_layout_mode forKey:@"voidLayoutMode"];
        [self setNeedsDisplay:YES];
        return;
    }
    if (btn == 2) {
        // Cycle to next tab.
        if (g_num_tabs > 1) {
            int next = (g_active_tab + 1) % g_num_tabs;
            if (g_active_tab >= 0 && g_active_tab < MAX_TABS) {
                memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
                g_tabs[g_active_tab].cur_row = g_term_cur_row;
                g_tabs[g_active_tab].cur_col = g_term_cur_col;
            }
            g_active_tab = next;
            memcpy(g_term_grid, g_tabs[next].grid, sizeof(g_term_grid));
            g_term_cur_row = g_tabs[next].cur_row;
            g_term_cur_col = g_tabs[next].cur_col;
            g_scroll_offset = 0;
            g_tab_cmd = 3;
            g_full_redraw = 1;
            clear_active_alarm();
            [self setNeedsDisplay:YES];
        }
        return;
    }

    // Grid mode: hit-test against all tiles and switch to the one under
    // the click. Tab bar + drag-reorder are disabled in grid mode (the
    // bar isn't drawn and tiles already visually distinguish tabs).
    if (g_layout_mode == LAYOUT_GRID && g_num_tabs >= 1 && g_num_tabs <= 9) {
        NSRect bounds = [self bounds];
        for (int k = 0; k < g_num_tabs; k++) {
            NSRect tile = compute_tile_rect(k, bounds, g_num_tabs);
            if (NSPointInRect(p, tile)) {
                if (k != g_active_tab) {
                    // Save active → old tab slot and load new tab. Same
                    // pattern as the stacked path so the hexa VT state
                    // round-trips cleanly on switch.
                    if (g_active_tab >= 0 && g_active_tab < MAX_TABS) {
                        memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
                        g_tabs[g_active_tab].cur_row = g_term_cur_row;
                        g_tabs[g_active_tab].cur_col = g_term_cur_col;
                    }
                    g_active_tab = k;
                    memcpy(g_term_grid, g_tabs[k].grid, sizeof(g_term_grid));
                    g_term_cur_row = g_tabs[k].cur_row;
                    g_term_cur_col = g_tabs[k].cur_col;
                    g_tab_cmd = 3;
                    g_scroll_offset = 0;
                    clear_active_alarm();
                    [self setNeedsDisplay:YES];
                }
                return;
            }
        }
        return;
    }

    int eff_tbw = effective_tab_bar_w();
    if (eff_tbw > 0 && p.x < eff_tbw) {
        int idx = (int)((p.y - 4) / TAB_ROW_H);
        if (idx >= 0 && idx < g_num_tabs) {
            // Seed drag state — a plain click still switches tabs below,
            // and mouseDragged will flip g_drag_active once the cursor
            // has moved past a small threshold.
            g_drag_source = idx;
            g_drag_target = idx;
            g_drag_active = 0;
            g_drag_origin = p;

            if (idx != g_active_tab) {
                // Save current grid to old tab
                if (g_active_tab >= 0 && g_active_tab < MAX_TABS) {
                    memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
                    g_tabs[g_active_tab].cur_row = g_term_cur_row;
                    g_tabs[g_active_tab].cur_col = g_term_cur_col;
                }
                g_active_tab = idx;
                // Load new tab's grid
                memcpy(g_term_grid, g_tabs[idx].grid, sizeof(g_term_grid));
                g_term_cur_row = g_tabs[idx].cur_row;
                g_term_cur_col = g_tabs[idx].cur_col;
                // Signal hexa to reload screen from C
                g_tab_cmd = 3; // 3 = switched (hexa reloads)
                g_scroll_offset = 0;
                clear_active_alarm();
                // Switching tabs invalidates any ongoing selection.
                clear_selection();
                [self setNeedsDisplay:YES];
            }
        }
        return;
    }
    // ── Mouse selection start (terminal grid area) ──
    if (g_term_cw <= 0 || g_term_ch <= 0) return;
    int col = (int)((p.x - eff_tbw) / g_term_cw);
    int row = (int)(p.y / g_term_ch);
    if (col < 0) col = 0;
    if (row < 0) row = 0;
    if (col >= g_term_cols) col = g_term_cols - 1;
    if (row >= g_term_rows) row = g_term_rows - 1;

    // Remember the click was in the grid area so mouseDragged extends
    // the selection rather than triggering tab drag reorder.
    g_sel_anchor_in_grid = 1;
    g_drag_source = -1; // ensure tab-drag path stays disabled
    g_drag_target = -1;
    g_drag_active = 0;
    g_drag_origin = p;
    g_sel_click_count = (int)[event clickCount];

    if (g_sel_click_count >= 3) {
        // Triple-click: select whole line.
        g_sel_start_row = row;
        g_sel_start_col = 0;
        g_sel_end_row = row;
        g_sel_end_col = (g_term_cols > 0) ? g_term_cols - 1 : 0;
        g_sel_active = 1;
        [self setNeedsDisplay:YES];
        return;
    }
    if (g_sel_click_count == 2) {
        // Double-click: select the word under the cursor (contiguous
        // run of non-space glyphs). Uses the LIVE grid only — matches
        // macOS Terminal.app behavior in scrollback.
        int c0 = col, c1 = col;
        if (row >= 0 && row < g_term_rows) {
            TermCell *rowp = g_term_grid[row];
            // If the clicked cell itself is blank, we still produce a
            // single-column selection so the user has visual feedback.
            if (rowp[col].ch > ' ') {
                while (c0 > 0 && rowp[c0 - 1].ch > ' ') c0--;
                while (c1 < g_term_cols - 1 && rowp[c1 + 1].ch > ' ') c1++;
            }
        }
        g_sel_start_row = row;
        g_sel_start_col = c0;
        g_sel_end_row = row;
        g_sel_end_col = c1;
        g_sel_active = 1;
        [self setNeedsDisplay:YES];
        return;
    }
    // Single click: seed an inert selection. Becomes active once the
    // user drags past the origin; plain clicks just clear the previous
    // selection (if any) without leaving a stray highlight.
    g_sel_start_row = row;
    g_sel_start_col = col;
    g_sel_end_row = row;
    g_sel_end_col = col;
    g_sel_active = 0;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];

    // ── Tab-bar drag reorder path ──
    if (g_drag_source >= 0) {
        if (!g_drag_active) {
            CGFloat dx = p.x - g_drag_origin.x;
            CGFloat dy = p.y - g_drag_origin.y;
            if ((dx * dx + dy * dy) < 16.0) return; // 4px threshold
            g_drag_active = 1;
        }

        // Compute drop slot from the current y position. Clamp to the
        // existing tab range so dragging past the end just pins to the
        // last slot instead of creating a phantom target.
        int target = (int)((p.y - 4) / TAB_ROW_H);
        if (target < 0) target = 0;
        if (target >= g_num_tabs) target = g_num_tabs - 1;
        if (target != g_drag_target) {
            g_drag_target = target;
            int eff_tbw = effective_tab_bar_w();
            if (eff_tbw > 0)
                [self setNeedsDisplayInRect:NSMakeRect(0, 0, eff_tbw,
                                                       [self bounds].size.height)];
        }
        return;
    }

    // ── Terminal grid selection path ──
    if (!g_sel_anchor_in_grid) return;
    if (g_term_cw <= 0 || g_term_ch <= 0) return;
    int eff_tbw = effective_tab_bar_w();
    int col = (int)((p.x - eff_tbw) / g_term_cw);
    int row = (int)(p.y / g_term_ch);
    if (col < 0) col = 0;
    if (row < 0) row = 0;
    if (col >= g_term_cols) col = g_term_cols - 1;
    if (row >= g_term_rows) row = g_term_rows - 1;

    // Only arm the selection once the cursor actually moves to a
    // different cell — matches Terminal.app: a click-without-drag
    // doesn't leave a stray highlight.
    if (!g_sel_active) {
        if (row != g_sel_start_row || col != g_sel_start_col) {
            g_sel_active = 1;
        }
    }
    g_sel_end_row = row;
    g_sel_end_col = col;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (g_drag_source >= 0) {
        if (g_drag_active && g_drag_source != g_drag_target &&
            g_drag_target >= 0) {
            tabs_move(g_drag_source, g_drag_target);
            [self setNeedsDisplay:YES];
        }
        g_drag_source = -1;
        g_drag_target = -1;
        g_drag_active = 0;
        return;
    }
    // Terminal grid selection: nothing to finalize — state stays live
    // until ESC, a keystroke, or a fresh click. If we never armed the
    // selection (plain click, no drag), collapse it so there's no
    // residual highlight painted next frame.
    if (g_sel_anchor_in_grid && !g_sel_active) {
        clear_selection();
        [self setNeedsDisplay:YES];
    }
    g_sel_anchor_in_grid = 0;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags mods = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (!(mods & NSEventModifierFlagCommand)) return [super performKeyEquivalent:event];

    NSString *raw = [event charactersIgnoringModifiers];
    if (!raw.length) return [super performKeyEquivalent:event];
    unichar ch = [raw characterAtIndex:0];
    int with_ctrl = (mods & NSEventModifierFlagControl) != 0;

    if (ch == 't') { g_tab_cmd = 1; return YES; } // Cmd+T new tab
    if (ch == 'w') { g_tab_cmd = 2; return YES; } // Cmd+W close tab
    if (ch == 'q') { g_term_quit = 1; return YES; } // Cmd+Q quit
    // Cmd+Z → undo the most recent tab close (reopen same profile fresh).
    if (ch == 'z' && !(mods & NSEventModifierFlagShift)) {
        tab_reopen_last();
        return YES;
    }
    // Cmd+C / Cmd+V clipboard — Ctrl+C must still pass through as SIGINT.
    if (ch == 'c' && !with_ctrl) {
        copy_selection_to_clipboard();
        return YES;
    }
    if (ch == 'v' && !with_ctrl) {
        paste_from_clipboard();
        if (g_scroll_offset > 0) { g_scroll_offset = 0; g_full_redraw = 1; }
        clear_selection();
        [self setNeedsDisplay:YES];
        return YES;
    }
    // Cmd+F toggle search overlay.
    if ((ch == 'f' || ch == 'F') && !with_ctrl) {
        if (g_search_active) search_close();
        else                 search_open();
        [self setNeedsDisplay:YES];
        return YES;
    }
    // Cmd+G → toggle tiling grid layout. Fires g_layout_dirty so the main
    // event loop picks up the change on the next tick and sends TIOCSWINSZ
    // to each tab. 10+ tabs can't enter grid mode (falls back to stacked).
    if (ch == 'g') {
        if (g_num_tabs >= 1 && g_num_tabs <= 9)
            g_layout_mode = (g_layout_mode == LAYOUT_GRID) ? LAYOUT_STACKED : LAYOUT_GRID;
        else
            g_layout_mode = LAYOUT_STACKED;
        g_layout_dirty = 1;
        g_full_redraw = 1;
        g_eff_tab_bar_w_cache = -1;
        // Persist across restarts.
        @autoreleasepool {
            [[NSUserDefaults standardUserDefaults]
                setInteger:(NSInteger)g_layout_mode forKey:@"voidLayoutMode"];
        }
        [self setNeedsDisplay:YES];
        return YES;
    }
    // Cmd+1~9 → tab 1..9, Cmd+0 → tab 10
    int target = -1;
    if (ch >= '1' && ch <= '9') target = ch - '1';
    else if (ch == '0')          target = 9;
    if (target >= 0) {
        if (target < g_num_tabs && target != g_active_tab) {
            if (g_active_tab >= 0 && g_active_tab < MAX_TABS) {
                memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
                g_tabs[g_active_tab].cur_row = g_term_cur_row;
                g_tabs[g_active_tab].cur_col = g_term_cur_col;
            }
            g_active_tab = target;
            memcpy(g_term_grid, g_tabs[target].grid, sizeof(g_term_grid));
            g_term_cur_row = g_tabs[target].cur_row;
            g_term_cur_col = g_tabs[target].cur_col;
            g_tab_cmd = 3; // signal hexa to reload
            g_scroll_offset = 0;
            clear_active_alarm();
            [self setNeedsDisplay:YES];
        }
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags mods = [event modifierFlags];

    // Cmd+key already handled by performKeyEquivalent
    if (mods & NSEventModifierFlagCommand) return;

    NSString *chars = [event characters];
    if (!chars.length) return;
    unichar ch = [chars characterAtIndex:0];

    // ── Search overlay keyboard handling ──
    // When the Cmd+F overlay is open, this view absorbs all keystrokes:
    // text feeds the query, Enter walks forward through matches, ESC
    // closes. Nothing is forwarded to the PTY while the overlay is up.
    if (g_search_active) {
        // ESC closes the overlay.
        if (ch == 27) {
            search_close();
            [self setNeedsDisplay:YES];
            return;
        }
        // Enter → next match. Shift+Enter → previous.
        if (ch == '\r' || ch == '\n') {
            if (mods & NSEventModifierFlagShift) search_prev();
            else                                  search_next();
            [self setNeedsDisplay:YES];
            return;
        }
        // Up arrow → previous match. Down arrow → next match.
        if (ch == NSUpArrowFunctionKey) {
            search_prev();
            [self setNeedsDisplay:YES];
            return;
        }
        if (ch == NSDownArrowFunctionKey) {
            search_next();
            [self setNeedsDisplay:YES];
            return;
        }
        // Backspace.
        if (ch == 0x7f || ch == 0x08) {
            search_backspace();
            [self setNeedsDisplay:YES];
            return;
        }
        // Printable / UTF-8 passthrough. characters returns the composed
        // output after modifier processing so shifted chars are correct.
        // Skip the remaining C0 control codes (NSEvent can deliver them
        // from Ctrl+letter combos); we don't want those in the query.
        if (ch >= 32 && ch < 0xF700) {
            const char *utf8 = [chars UTF8String];
            if (utf8) search_append_bytes(utf8, (int)strlen(utf8));
            [self setNeedsDisplay:YES];
            return;
        }
        // Any other function key (page up/down, home/end, etc.) — swallow.
        return;
    }

    // Shift+PageUp/Down: scrollback navigation (don't send to PTY)
    if (mods & NSEventModifierFlagShift) {
        if (ch == NSPageUpFunctionKey) {
            VoidTab *tab = (g_active_tab >= 0 && g_active_tab < g_num_tabs) ? &g_tabs[g_active_tab] : NULL;
            g_scroll_offset += g_term_rows;
            int max_sb = tab ? tab->sb_total : 0;
            if (g_scroll_offset > max_sb) g_scroll_offset = max_sb;
            [self setNeedsDisplay:YES];
            return;
        }
        if (ch == NSPageDownFunctionKey) {
            g_scroll_offset -= g_term_rows;
            if (g_scroll_offset < 0) g_scroll_offset = 0;
            [self setNeedsDisplay:YES];
            return;
        }
    }

    // Any PTY-bound key resets scrollback to live view
    if (g_scroll_offset > 0) {
        g_scroll_offset = 0;
        [self setNeedsDisplay:YES];
    }

    // Any PTY-bound keystroke (including ESC) clears the selection —
    // mirrors macOS Terminal.app so the highlight doesn't linger while
    // you're typing the next command.
    if (g_sel_start_row >= 0) {
        clear_selection();
        [self setNeedsDisplay:YES];
    }

    // Ctrl+Backspace: kill line (send Ctrl+U)
    if ((mods & NSEventModifierFlagControl) && ch == 0x7f) {
        char ctrl_u = 0x15;
        term_key_push(&ctrl_u, 1);
        return;
    }

    // Ctrl+key
    if (mods & NSEventModifierFlagControl) {
        NSString *raw = [event charactersIgnoringModifiers];
        if (raw.length > 0) {
            unichar rch = [raw characterAtIndex:0];
            if (rch >= 'a' && rch <= 'z') {
                char ctrl = rch - 'a' + 1;
                term_key_push(&ctrl, 1);
                return;
            }
        }
    }

    switch (ch) {
        case NSUpArrowFunctionKey:    term_key_push("\033[A", 3); return;
        case NSDownArrowFunctionKey:  term_key_push("\033[B", 3); return;
        case NSRightArrowFunctionKey: term_key_push("\033[C", 3); return;
        case NSLeftArrowFunctionKey:  term_key_push("\033[D", 3); return;
        case NSHomeFunctionKey:       term_key_push("\033[H", 3); return;
        case NSEndFunctionKey:        term_key_push("\033[F", 3); return;
        case NSPageUpFunctionKey:     term_key_push("\033[5~", 4); return;
        case NSPageDownFunctionKey:   term_key_push("\033[6~", 4); return;
        case NSDeleteFunctionKey:     term_key_push("\033[3~", 4); return;
    }
    const char *utf8 = [chars UTF8String];
    term_key_push(utf8, (int)strlen(utf8));
}
- (void)scrollWheel:(NSEvent *)event {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return;
    VoidTab *tab = &g_tabs[g_active_tab];
    float dy = [event scrollingDeltaY];
    if ([event hasPreciseScrollingDeltas]) {
        // Trackpad: accumulate sub-line deltas
        static float accum = 0;
        accum += dy;
        if (accum > g_term_ch / 2) {
            g_scroll_offset += (int)(accum / (g_term_ch / 2));
            accum = fmodf(accum, g_term_ch / 2);
        } else if (accum < -(g_term_ch / 2)) {
            g_scroll_offset += (int)(accum / (g_term_ch / 2));
            accum = fmodf(accum, g_term_ch / 2);
        }
    } else {
        // Mouse wheel: discrete lines
        if (dy > 0) g_scroll_offset += 3;
        else if (dy < 0) g_scroll_offset -= 3;
    }
    if (g_scroll_offset < 0) g_scroll_offset = 0;
    int max_sb = tab->sb_total;
    if (g_scroll_offset > max_sb) g_scroll_offset = max_sb;
    [self setNeedsDisplay:YES];
}
- (void)flagsChanged:(NSEvent *)e {}
@end

// ── App delegate ──
@interface HexaTermDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate>
// Menu bar action targets — thin wrappers over the same flags the
// Cmd-intercept path uses.
- (void)menuNewTab:(id)sender;
- (void)menuCloseTab:(id)sender;
- (void)menuUndoClose:(id)sender;
- (void)menuCopy:(id)sender;
- (void)menuPaste:(id)sender;
- (void)menuFind:(id)sender;
- (void)menuZoomIn:(id)sender;
- (void)menuZoomOut:(id)sender;
- (void)menuZoomReset:(id)sender;
- (void)menuLayoutStacked:(id)sender;
- (void)menuLayoutGrid:(id)sender;
- (void)menuCycleNext:(id)sender;
// Hidden-sessions submenu: populated on open via menuNeedsUpdate:,
// each item's representedObject holds the 32-byte session_id as
// NSData, and menuAttachHiddenSession: sends ATTACH + adds a new tab.
- (void)menuAttachHiddenSession:(id)sender;
@end
@implementation HexaTermDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }
- (void)applicationWillTerminate:(NSNotification *)n { g_term_quit = 1; }
- (void)windowWillClose:(NSNotification *)n { g_term_quit = 1; }

// Menu actions — each mirrors the equivalent Cmd-intercept branch so
// a menu click produces the same state transition as the keyboard
// shortcut. All of them request a redraw on the main window.
- (void)menuNewTab:(id)sender  { (void)sender; g_tab_cmd = 1; }
- (void)menuCloseTab:(id)sender { (void)sender; g_tab_cmd = 2; }
- (void)menuUndoClose:(id)sender {
    (void)sender;
    tab_reopen_last();
}
- (void)menuCopy:(id)sender     { (void)sender; copy_selection_to_clipboard(); }
- (void)menuPaste:(id)sender {
    (void)sender;
    paste_from_clipboard();
    if (g_scroll_offset > 0) { g_scroll_offset = 0; g_full_redraw = 1; }
    clear_selection();
    if (g_window) [[g_window contentView] setNeedsDisplay:YES];
}
- (void)menuFind:(id)sender {
    (void)sender;
    if (g_search_active) search_close();
    else                 search_open();
    if (g_window) [[g_window contentView] setNeedsDisplay:YES];
}
- (void)menuZoomIn:(id)sender {
    (void)sender;
    set_font_size(g_font_size + 1);
    g_eff_tab_bar_w_cache = -1;
    g_resized = 1;
    g_full_redraw = 1;
    if (g_window) [[g_window contentView] setNeedsDisplay:YES];
}
- (void)menuZoomOut:(id)sender {
    (void)sender;
    set_font_size(g_font_size - 1);
    g_eff_tab_bar_w_cache = -1;
    g_resized = 1;
    g_full_redraw = 1;
    if (g_window) [[g_window contentView] setNeedsDisplay:YES];
}
- (void)menuZoomReset:(id)sender {
    (void)sender;
    set_font_size(13);
    g_eff_tab_bar_w_cache = -1;
    g_resized = 1;
    g_full_redraw = 1;
    if (g_window) [[g_window contentView] setNeedsDisplay:YES];
}
- (void)menuLayoutStacked:(id)sender {
    (void)sender;
    g_layout_mode = LAYOUT_STACKED;
    g_layout_dirty = 1;
    g_full_redraw = 1;
    g_eff_tab_bar_w_cache = -1;
    [[NSUserDefaults standardUserDefaults]
        setInteger:(NSInteger)g_layout_mode forKey:@"voidLayoutMode"];
    if (g_window) [[g_window contentView] setNeedsDisplay:YES];
}
- (void)menuLayoutGrid:(id)sender {
    (void)sender;
    if (g_num_tabs >= 1 && g_num_tabs <= 9) g_layout_mode = LAYOUT_GRID;
    else                                     g_layout_mode = LAYOUT_STACKED;
    g_layout_dirty = 1;
    g_full_redraw = 1;
    g_eff_tab_bar_w_cache = -1;
    [[NSUserDefaults standardUserDefaults]
        setInteger:(NSInteger)g_layout_mode forKey:@"voidLayoutMode"];
    if (g_window) [[g_window contentView] setNeedsDisplay:YES];
}
- (void)menuCycleNext:(id)sender {
    (void)sender;
    if (g_num_tabs <= 1) return;
    int next = (g_active_tab + 1) % g_num_tabs;
    if (g_active_tab >= 0 && g_active_tab < MAX_TABS) {
        memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
        g_tabs[g_active_tab].cur_row = g_term_cur_row;
        g_tabs[g_active_tab].cur_col = g_term_cur_col;
    }
    g_active_tab = next;
    memcpy(g_term_grid, g_tabs[next].grid, sizeof(g_term_grid));
    g_term_cur_row = g_tabs[next].cur_row;
    g_term_cur_col = g_tabs[next].cur_col;
    g_scroll_offset = 0;
    g_tab_cmd = 3;
    g_full_redraw = 1;
    clear_active_alarm();
    if (g_window) [[g_window contentView] setNeedsDisplay:YES];
}
@end

static HexaTermDelegate *g_term_delegate = nil;

// ── Profile-driven tab shortcuts (Cmd+Ctrl+1~9) ──
//
// Profiles are loaded from ~/.void/profiles.json at startup. Each profile
// has: key ("1"~"9"), title, path, cmd. Cmd+Ctrl+N creates a new tab
// that cd's into `path` and runs `cmd`.
//
// Title dedup: if a tab with that title already exists, the new tab is
// titled "<title> (2)", "<title> (3)", etc.
//
// Resource isolation (docker-lite): each spawned child applies
// setrlimit(RLIMIT_NOFILE / RLIMIT_CPU / RLIMIT_AS) and setpriority(nice)
// so no single tab can monopolize the host's resources.

#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <pwd.h>

#define MAX_PROFILES 16
typedef struct VoidProfile_ {
    char key[4];     // "0".."9"
    char title[64];
    char path[512];
    char cmd[512];
    // Per-profile resource limits (0 = use defaults)
    long rl_mem_mb;  // RLIMIT_AS
    long rl_cpu_sec; // RLIMIT_CPU
    long rl_nofile;  // RLIMIT_NOFILE
    int  rl_nice;    // setpriority increment
} VoidProfile;

static VoidProfile g_profiles[MAX_PROFILES];
static int g_num_profiles = 0;

// Default resource caps applied even when profile is silent.
// These are per-child, enforced by the kernel, so a runaway shell
// can't wedge the host.
#define DEFAULT_RLIMIT_NOFILE 4096
#define DEFAULT_RLIMIT_AS_MB  4096   // 4 GB virtual address space
#define DEFAULT_RLIMIT_CPU    0      // 0 = don't cap cpu (interactive)
#define DEFAULT_NICE          0      // 0 = normal priority

static void expand_tilde(const char *in, char *out, size_t outsz) {
    if (in[0] == '~' && (in[1] == '/' || in[1] == 0)) {
        const char *home = getenv("HOME");
        if (!home) {
            struct passwd *pw = getpwuid(getuid());
            home = pw ? pw->pw_dir : "/";
        }
        snprintf(out, outsz, "%s%s", home, in + 1);
    } else {
        snprintf(out, outsz, "%s", in);
    }
}

// Load profiles from ~/.void/profiles.json. Silently no-ops if the file
// doesn't exist. Uses NSJSONSerialization — we're already in ObjC so it's
// free. If the file is missing, also write out a default template that
// matches the user's request so they have something to edit.
static void load_profiles(void) {
    @autoreleasepool {
        char cfg_dir[512], cfg_path[600];
        expand_tilde("~/.void", cfg_dir, sizeof(cfg_dir));
        snprintf(cfg_path, sizeof(cfg_path), "%s/profiles.json", cfg_dir);

        NSString *pathNS = [NSString stringWithUTF8String:cfg_path];
        NSData *data = [NSData dataWithContentsOfFile:pathNS];

        if (!data) {
            // Seed a default template so the user has something to edit.
            mkdir(cfg_dir, 0755);
            NSString *tpl = @"{\n"
                "  \"profiles\": [\n"
                "    { \"key\": \"1\", \"title\": \"nexus\",         \"path\": \"~/Dev/nexus\",            \"cmd\": \"cl\" },\n"
                "    { \"key\": \"2\", \"title\": \"anima\",         \"path\": \"~/Dev/anima\",            \"cmd\": \"cl\" },\n"
                "    { \"key\": \"3\", \"title\": \"n6-architecture\", \"path\": \"~/Dev/n6-architecture\",  \"cmd\": \"cl\" },\n"
                "    { \"key\": \"4\", \"title\": \"contribution\",  \"path\": \"~/Dev/contribution\",     \"cmd\": \"cl\" },\n"
                "    { \"key\": \"5\", \"title\": \"prism\",         \"path\": \"~/mango/hexa-lang\",      \"cmd\": \"cl\" },\n"
                "    { \"key\": \"6\", \"title\": \"prism-manager\", \"path\": \"~/mango/prism-manager\",  \"cmd\": \"cl\" },\n"
                "    { \"key\": \"7\", \"title\": \"void\",          \"path\": \"~/Dev/void\",             \"cmd\": \"cl\" },\n"
                "    { \"key\": \"8\", \"title\": \"airgenome\",     \"path\": \"~/Dev/airgenome\",        \"cmd\": \"cl\" },\n"
                "    { \"key\": \"9\", \"title\": \"hexa-lang\",     \"path\": \"~/Dev/hexa-lang\",        \"cmd\": \"cl\" },\n"
                "    { \"key\": \"0\", \"title\": \"home\",          \"path\": \"~\",                      \"cmd\": \"\" }\n"
                "  ]\n"
                "}\n";
            [tpl writeToFile:pathNS atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            data = [NSData dataWithContentsOfFile:pathNS];
            if (!data) return;
        }

        NSError *err = nil;
        id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (err || ![root isKindOfClass:[NSDictionary class]]) return;
        NSArray *arr = root[@"profiles"];
        if (![arr isKindOfClass:[NSArray class]]) return;

        g_num_profiles = 0;
        for (NSDictionary *p in arr) {
            if (g_num_profiles >= MAX_PROFILES) break;
            if (![p isKindOfClass:[NSDictionary class]]) continue;
            NSString *k = p[@"key"];
            NSString *t = p[@"title"];
            NSString *pa = p[@"path"];
            NSString *c = p[@"cmd"];
            if (![k isKindOfClass:[NSString class]] ||
                ![t isKindOfClass:[NSString class]] ||
                ![pa isKindOfClass:[NSString class]]) continue;

            VoidProfile *vp = &g_profiles[g_num_profiles];
            snprintf(vp->key,   sizeof(vp->key),   "%s", [k UTF8String]);
            snprintf(vp->title, sizeof(vp->title), "%s", [t UTF8String]);
            char expanded[512];
            expand_tilde([pa UTF8String], expanded, sizeof(expanded));
            snprintf(vp->path,  sizeof(vp->path),  "%s", expanded);
            snprintf(vp->cmd,   sizeof(vp->cmd),   "%s", c ? [c UTF8String] : "");

            NSNumber *mem = p[@"rl_mem_mb"];
            NSNumber *cpu = p[@"rl_cpu_sec"];
            NSNumber *nof = p[@"rl_nofile"];
            NSNumber *nic = p[@"rl_nice"];
            vp->rl_mem_mb  = [mem isKindOfClass:[NSNumber class]] ? [mem longValue] : 0;
            vp->rl_cpu_sec = [cpu isKindOfClass:[NSNumber class]] ? [cpu longValue] : 0;
            vp->rl_nofile  = [nof isKindOfClass:[NSNumber class]] ? [nof longValue] : 0;
            vp->rl_nice    = [nic isKindOfClass:[NSNumber class]] ? [nic intValue]  : 0;

            g_num_profiles++;
        }
    }
}

// Find profile by single-digit key ("0".."9"). NULL if no match.
static VoidProfile *profile_by_key(char ch) {
    char key[2] = { ch, 0 };
    for (int i = 0; i < g_num_profiles; i++) {
        if (strcmp(g_profiles[i].key, key) == 0) return &g_profiles[i];
    }
    return NULL;
}

// Find profile by title (used by undo-close to look up original cmd).
// Matches exact title, not fuzzy — profile_base is already the exact
// string we stored at open time.
static VoidProfile *profile_by_title(const char *title) {
    if (!title || !*title) return NULL;
    for (int i = 0; i < g_num_profiles; i++) {
        if (strcmp(g_profiles[i].title, title) == 0) return &g_profiles[i];
    }
    return NULL;
}

// Pop the most recently closed tab and respawn it. Called from the
// Cmd+Z handler. The new tab is a FRESH spawn — the shell/PTY and
// whatever was running in the old tab are gone; only the profile
// config (title, path, cmd) is restored. Like Chrome's Cmd+Shift+T.
// After creation, the tab is moved back to its original slot via
// g_reopen_target_idx / tabs_move so the order is preserved.
static void tab_reopen_last(void) {
    if (g_closed_count <= 0) return;
    g_closed_count--;
    ClosedTabSnapshot *snap = &g_closed_stack[g_closed_count];

    static VoidProfile scratch;
    memset(&scratch, 0, sizeof(scratch));
    const char *label = snap->profile_base[0] ? snap->profile_base : snap->title;
    snprintf(scratch.title, sizeof(scratch.title), "%s", label);
    snprintf(scratch.path,  sizeof(scratch.path),  "%s", snap->cwd);

    VoidProfile *p = profile_by_title(label);
    if (p) {
        snprintf(scratch.cmd, sizeof(scratch.cmd), "%s", p->cmd);
        snprintf(scratch.key, sizeof(scratch.key), "%s", p->key);
        scratch.rl_mem_mb  = p->rl_mem_mb;
        scratch.rl_cpu_sec = p->rl_cpu_sec;
        scratch.rl_nofile  = p->rl_nofile;
        scratch.rl_nice    = p->rl_nice;
    }

    // Record where the tab should end up. Clamp to current tab count
    // so we don't request an impossible slot when tabs have been
    // closed in between.
    int target = snap->original_idx;
    if (target < 0) target = 0;
    if (target > g_num_tabs) target = g_num_tabs; // will become new end
    g_reopen_target_idx = target;

    g_pending_profile = &scratch;
    g_tab_cmd = 1;
}

// Apply docker-lite resource limits to the current (child) process.
static void apply_rlimits(VoidProfile *vp) {
    struct rlimit rl;

    // RLIMIT_NOFILE — bound descriptor count
    long nofile = (vp && vp->rl_nofile > 0) ? vp->rl_nofile : DEFAULT_RLIMIT_NOFILE;
    rl.rlim_cur = (rlim_t)nofile;
    rl.rlim_max = (rlim_t)nofile;
    setrlimit(RLIMIT_NOFILE, &rl);

    // RLIMIT_AS — virtual address space (cap memory)
    long mem_mb = (vp && vp->rl_mem_mb > 0) ? vp->rl_mem_mb : DEFAULT_RLIMIT_AS_MB;
    if (mem_mb > 0) {
        rl.rlim_cur = (rlim_t)mem_mb * 1024L * 1024L;
        rl.rlim_max = rl.rlim_cur;
        setrlimit(RLIMIT_AS, &rl);
    }

    // RLIMIT_CPU — soft CPU cap in seconds (0 = unlimited)
    long cpu_sec = (vp && vp->rl_cpu_sec > 0) ? vp->rl_cpu_sec : DEFAULT_RLIMIT_CPU;
    if (cpu_sec > 0) {
        rl.rlim_cur = (rlim_t)cpu_sec;
        rl.rlim_max = (rlim_t)cpu_sec + 5;
        setrlimit(RLIMIT_CPU, &rl);
    }

    // Nice level — lower CPU priority if requested
    int nice_lvl = (vp && vp->rl_nice > 0) ? vp->rl_nice : DEFAULT_NICE;
    if (nice_lvl > 0) setpriority(PRIO_PROCESS, 0, nice_lvl);

    // Process group — decouple from parent so a crash doesn't kill void.
    setsid();
}

// ── Tab management (C-internal) ──

// ── void-server client glue ─────────────────────────────────────────
//
// When VOID_USE_SERVER=1 is set, tab spawn and close route through the
// void-server daemon (src/void_server.c) so that PTY sessions survive
// void_term exit / crash / hot-swap.
//
// Flow:
//   startup → ensure_void_server() forks void_server if no socket
//   new tab → void_server_spawn() sends SPAWN, receives fd via SCM_RIGHTS
//             + session_id (ULID). g_tabs[idx].session_id[32] stores it.
//   close   → void_server_detach() sends DETACH, closes local fd; server
//             keeps the session alive on its side.
//
// Without VOID_USE_SERVER the direct forkpty path still works — this is
// strictly additive for v1 so the integration can ship without breaking
// existing tests.
#define VS_MAGIC_CLIENT    0x31525356u
#define VS_SOCK_PATH       "/tmp/void_server.sock"
#define VS_CMD_SPAWN       1
#define VS_CMD_ATTACH      2
#define VS_CMD_DETACH      3
#define VS_CMD_LIST        4
#define VS_CMD_KILL        5
#define VS_CMD_PING        7

static int  g_server_sock = -1;
static int  g_use_server  = -1;  // -1 = not decided, 0/1 = resolved

static int void_server_enabled(void) {
    if (g_use_server < 0) {
        // Server-backed mode is ON by default so PTY sessions survive
        // void_term kill+relaunch (auto-build hook uses this path).
        // Set VOID_NO_SERVER=1 to opt out and fall back to direct fork.
        const char *off = getenv("VOID_NO_SERVER");
        g_use_server = (off && off[0] == '1') ? 0 : 1;
    }
    return g_use_server;
}

static int void_server_try_connect(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", VS_SOCK_PATH);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

// Fork the void_server binary expected to live next to void_term. The
// server double-forks internally so the grandchild is orphaned to init.
static void void_server_spawn_daemon(void) {
    pid_t p = fork();
    if (p < 0) return;
    if (p == 0) {
        char exe[4096];
        uint32_t sz = sizeof(exe);
        if (_NSGetExecutablePath(exe, &sz) == 0) {
            char *slash = strrchr(exe, '/');
            if (slash) {
                strcpy(slash + 1, "void_server");
                execl(exe, "void_server", (char *)NULL);
            }
        }
        execlp("void_server", "void_server", (char *)NULL);
        _exit(127);
    }
    // Wait briefly for the socket to appear
    for (int i = 0; i < 100; i++) {
        struct stat st;
        if (stat(VS_SOCK_PATH, &st) == 0 && S_ISSOCK(st.st_mode)) break;
        usleep(10 * 1000);
    }
    waitpid(p, NULL, WNOHANG);
}

static int void_server_ensure(void) {
    if (!void_server_enabled()) return -1;
    if (g_server_sock >= 0) return 0;
    g_server_sock = void_server_try_connect();
    if (g_server_sock >= 0) return 0;
    void_server_spawn_daemon();
    g_server_sock = void_server_try_connect();
    return g_server_sock >= 0 ? 0 : -1;
}

// recv exactly n bytes, blocking
static int vs_read_exact(int fd, void *buf, size_t n) {
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, (char *)buf + got, n - got);
        if (r <= 0) { if (r < 0 && errno == EINTR) continue; return -1; }
        got += (size_t)r;
    }
    return 0;
}

static int vs_write_exact(int fd, const void *buf, size_t n) {
    size_t sent = 0;
    while (sent < n) {
        ssize_t w = write(fd, (const char *)buf + sent, n - sent);
        if (w <= 0) { if (w < 0 && errno == EINTR) continue; return -1; }
        sent += (size_t)w;
    }
    return 0;
}

// Send SPAWN command, receive (status, session_id, pty_fd). Returns 0 on
// success. The caller owns pty_fd on return (the server also has its own
// copy).
static int void_server_spawn(const char *title, const char *cwd,
                             const char *cmd, int rows, int cols,
                             char out_id[32], int *out_fd) {
    if (void_server_ensure() != 0) return -1;

    // Request body: title[64] cwd[512] cmd[512] rows16 cols16
    char req[64 + 512 + 512 + 4] = {0};
    snprintf(req,               64,  "%s", title ?: "");
    snprintf(req + 64,          512, "%s", cwd   ?: "");
    snprintf(req + 64 + 512,    512, "%s", cmd   ?: "");
    uint16_t r16 = (uint16_t)rows, c16 = (uint16_t)cols;
    memcpy(req + 64 + 512 + 512,     &r16, 2);
    memcpy(req + 64 + 512 + 512 + 2, &c16, 2);

    uint32_t hdr[3] = { VS_MAGIC_CLIENT, VS_CMD_SPAWN, (uint32_t)sizeof(req) };
    if (vs_write_exact(g_server_sock, hdr, sizeof(hdr)) < 0) goto fail;
    if (vs_write_exact(g_server_sock, req, sizeof(req)) < 0) goto fail;

    // Receive response header + optional SCM_RIGHTS fd
    uint32_t rhdr[3];
    struct msghdr msg = {0};
    struct iovec iov = { rhdr, sizeof(rhdr) };
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    char ctrl[CMSG_SPACE(sizeof(int))];
    memset(ctrl, 0, sizeof(ctrl));
    msg.msg_control = ctrl;
    msg.msg_controllen = sizeof(ctrl);
    ssize_t r = recvmsg(g_server_sock, &msg, 0);
    if (r < (ssize_t)sizeof(rhdr)) goto fail;
    if (rhdr[0] != VS_MAGIC_CLIENT || rhdr[1] != 0) goto fail;

    int got_fd = -1;
    struct cmsghdr *cm = CMSG_FIRSTHDR(&msg);
    while (cm) {
        if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_RIGHTS) {
            memcpy(&got_fd, CMSG_DATA(cm), sizeof(int));
            break;
        }
        cm = CMSG_NXTHDR(&msg, cm);
    }
    if (got_fd < 0) goto fail;

    // Body: session_id[32] + uint32 hint
    char body[32 + 4] = {0};
    if (vs_read_exact(g_server_sock, body, sizeof(body)) < 0) {
        close(got_fd); goto fail;
    }
    memcpy(out_id, body, 32);
    int fl = fcntl(got_fd, F_GETFL, 0);
    fcntl(got_fd, F_SETFL, fl | O_NONBLOCK);
    *out_fd = got_fd;
    return 0;

fail:
    if (g_server_sock >= 0) { close(g_server_sock); g_server_sock = -1; }
    return -1;
}

// Send DETACH command. Server keeps the session alive.
static int void_server_detach(const char id[32]) {
    if (void_server_ensure() != 0) return -1;
    uint32_t hdr[3] = { VS_MAGIC_CLIENT, VS_CMD_DETACH, 32 };
    if (vs_write_exact(g_server_sock, hdr, sizeof(hdr)) < 0) goto fail;
    if (vs_write_exact(g_server_sock, id, 32) < 0) goto fail;
    uint32_t rhdr[3];
    if (vs_read_exact(g_server_sock, rhdr, sizeof(rhdr)) < 0) goto fail;
    // Drain body if any
    uint32_t body_len = rhdr[2];
    if (body_len > 0 && body_len < 1 << 20) {
        char skip[4096];
        uint32_t left = body_len;
        while (left > 0) {
            uint32_t chunk = left > sizeof(skip) ? sizeof(skip) : left;
            if (vs_read_exact(g_server_sock, skip, chunk) < 0) goto fail;
            left -= chunk;
        }
    }
    return 0;
fail:
    if (g_server_sock >= 0) { close(g_server_sock); g_server_sock = -1; }
    return -1;
}

// ── LIST + ATTACH client helpers ─────────────────────────────────────

typedef struct {
    char id[32];
    char label[64];
    char cwd[256];
    char processes[1024];
    int  proc_count;
} VsSessionEntry;

#define VS_LIST_MAX 64
static VsSessionEntry g_vs_list[VS_LIST_MAX];
static int g_vs_list_count = 0;

// Query the server for all live sessions. Fills g_vs_list. Returns the
// count or -1 on error.
static int void_server_list(void) {
    if (void_server_ensure() != 0) return -1;
    uint32_t hdr[3] = { VS_MAGIC_CLIENT, VS_CMD_LIST, 0 };
    if (vs_write_exact(g_server_sock, hdr, sizeof(hdr)) < 0) goto fail;

    uint32_t rhdr[3];
    if (vs_read_exact(g_server_sock, rhdr, sizeof(rhdr)) < 0) goto fail;
    if (rhdr[0] != VS_MAGIC_CLIENT) goto fail;
    uint32_t blen = rhdr[2];
    if (blen < 4 || blen > (1 << 20)) { g_vs_list_count = 0; return 0; }

    char *buf = (char *)malloc(blen);
    if (!buf) goto fail;
    if (vs_read_exact(g_server_sock, buf, blen) < 0) { free(buf); goto fail; }

    uint32_t n = 0;
    memcpy(&n, buf, 4);
    if (n > VS_LIST_MAX) n = VS_LIST_MAX;
    // Layout per entry must match void_server.c handle_list:
    //   id[32] label[64] cwd[256] uint32 proc_count names[32*32]
    const size_t each = 32 + 64 + 256 + 4 + 32 * 32;
    char *p = buf + 4;
    for (uint32_t i = 0; i < n; i++) {
        if ((size_t)(p - buf) + each > blen) break;
        memcpy(g_vs_list[i].id,    p,               32);
        memcpy(g_vs_list[i].label, p + 32,          64);
        memcpy(g_vs_list[i].cwd,   p + 32 + 64,     256);
        uint32_t pc = 0;
        memcpy(&pc, p + 32 + 64 + 256, 4);
        g_vs_list[i].proc_count = (int)pc;
        snprintf(g_vs_list[i].processes, sizeof(g_vs_list[i].processes),
                 "%s", p + 32 + 64 + 256 + 4);
        // Null-terminate fixed-size char arrays just in case
        g_vs_list[i].id[31] = 0;
        g_vs_list[i].label[63] = 0;
        g_vs_list[i].cwd[255] = 0;
        p += each;
    }
    free(buf);
    g_vs_list_count = (int)n;
    return (int)n;

fail:
    if (g_server_sock >= 0) { close(g_server_sock); g_server_sock = -1; }
    return -1;
}

// Attach to an existing session. On success writes the fd via SCM_RIGHTS
// into *out_fd and fills out_rows/out_cols from the server's reply. The
// grid payload that the server sends is read into a scratch buffer and
// discarded here — the client will let the reattached shell redraw
// itself (claude et al. redraw on SIGWINCH / focus in).
static int void_server_attach(const char id[32], int *out_fd,
                              int *out_rows, int *out_cols) {
    if (void_server_ensure() != 0) return -1;
    uint32_t hdr[3] = { VS_MAGIC_CLIENT, VS_CMD_ATTACH, 32 };
    if (vs_write_exact(g_server_sock, hdr, sizeof(hdr)) < 0) goto fail;
    if (vs_write_exact(g_server_sock, id, 32) < 0) goto fail;

    uint32_t rhdr[3];
    struct msghdr msg = {0};
    struct iovec iov = { rhdr, sizeof(rhdr) };
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    char ctrl[CMSG_SPACE(sizeof(int))];
    memset(ctrl, 0, sizeof(ctrl));
    msg.msg_control = ctrl;
    msg.msg_controllen = sizeof(ctrl);
    ssize_t r = recvmsg(g_server_sock, &msg, 0);
    if (r < (ssize_t)sizeof(rhdr)) goto fail;
    if (rhdr[0] != VS_MAGIC_CLIENT) goto fail;
    uint32_t status = rhdr[1];
    uint32_t blen = rhdr[2];
    // status 0 = live session w/ fd, status 3 = tombstone (no fd)
    if (status != 0) {
        if (blen > 0 && blen < (1 << 20)) {
            char *skip = (char *)malloc(blen);
            vs_read_exact(g_server_sock, skip, blen);
            free(skip);
        }
        return -1;
    }

    int got_fd = -1;
    struct cmsghdr *cm = CMSG_FIRSTHDR(&msg);
    while (cm) {
        if (cm->cmsg_level == SOL_SOCKET && cm->cmsg_type == SCM_RIGHTS) {
            memcpy(&got_fd, CMSG_DATA(cm), sizeof(int));
            break;
        }
        cm = CMSG_NXTHDR(&msg, cm);
    }
    if (got_fd < 0) return -1;

    // Body: rows16 cols16 uint32 grid_bytes + grid_data
    if (blen >= 8) {
        uint16_t rows = 0, cols = 0;
        if (vs_read_exact(g_server_sock, &rows, 2) < 0) { close(got_fd); goto fail; }
        if (vs_read_exact(g_server_sock, &cols, 2) < 0) { close(got_fd); goto fail; }
        uint32_t gb = 0;
        if (vs_read_exact(g_server_sock, &gb,   4) < 0) { close(got_fd); goto fail; }
        if (out_rows) *out_rows = rows;
        if (out_cols) *out_cols = cols;
        // Skip grid payload — we rely on the shell to redraw.
        if (gb > 0 && gb < (1 << 20)) {
            char *skip = (char *)malloc(gb);
            vs_read_exact(g_server_sock, skip, gb);
            free(skip);
        }
    }
    int fl = fcntl(got_fd, F_GETFL, 0);
    fcntl(got_fd, F_SETFL, fl | O_NONBLOCK);
    *out_fd = got_fd;
    return 0;

fail:
    if (g_server_sock >= 0) { close(g_server_sock); g_server_sock = -1; }
    return -1;
}

// Spawn a PTY with an optional profile. If vp is NULL, uses the user's
// $SHELL in login mode. If vp is non-NULL, the child cd's into vp->path
// and exec's `$SHELL -c "cd <path> && <cmd>; exec $SHELL"` so the user
// gets a live shell after the profile command finishes.
static int tab_spawn_pty_profile(VoidProfile *vp) {
    struct winsize ws;
    ws.ws_row = (unsigned short)g_term_rows;
    ws.ws_col = (unsigned short)g_term_cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) return -1;
    if (pid == 0) {
        setenv("TERM", "xterm-256color", 1);
        setenv("LANG", "en_US.UTF-8", 1);
        // Belt: when VOID.app is launched from Finder, LaunchServices
        // hands us a bare /usr/bin:/bin PATH. The profile cmd (e.g. `cl`)
        // lives under ~/.local/bin or /opt/homebrew/bin and would fail
        // with "command not found". Prepend the user's typical binary
        // dirs here — safe even when already present because login-mode
        // rc files just reorder them later.
        const char *old_path = getenv("PATH");
        char new_path[2048];
        snprintf(new_path, sizeof(new_path),
                 "%s/.local/bin:%s/bin:/opt/homebrew/bin:/usr/local/bin:%s",
                 getenv("HOME") ?: "", getenv("HOME") ?: "",
                 old_path ?: "/usr/bin:/bin");
        setenv("PATH", new_path, 1);
        apply_rlimits(vp);

        char *shell = getenv("SHELL");
        if (!shell) shell = "/bin/sh";

        if (vp) {
            // Build: cd <path> && <cmd>; exec <shell>
            // The trailing `exec $SHELL` keeps the tab alive after the
            // profile command terminates (so the user can keep working).
            if (chdir(vp->path) != 0) {
                // path missing — fall through to shell anyway
            }
            if (vp->cmd[0]) {
                char script[1200];
                snprintf(script, sizeof(script),
                         "%s; exec %s -l", vp->cmd, shell);
                // -l (login) loads ~/.zprofile/.zshrc so aliases and the
                // user's PATH are in place before the profile cmd runs.
                // Without -l, `cl` → alias is undefined in the subshell.
                execl(shell, shell, "-l", "-c", script, (char*)NULL);
            } else {
                execl(shell, shell, "-l", (char*)NULL);
            }
        } else {
            execl(shell, shell, "-l", (char*)NULL);
        }
        _exit(127);
    }
    int fl = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, fl | O_NONBLOCK);
    return master;
}

static int tab_spawn_pty(void) { return tab_spawn_pty_profile(NULL); }

static void tab_clear_grid(TermCell grid[TERM_MAX_ROWS][TERM_MAX_COLS]) {
    for (int r = 0; r < TERM_MAX_ROWS; r++)
        for (int c = 0; c < TERM_MAX_COLS; c++) {
            grid[r][c].ch = ' ';
            grid[r][c].fg = 7;
            grid[r][c].bg = 0;
            grid[r][c].flags = 0;
        }
}

// ── Public API ──

// Single-instance lock via Unix domain socket
#include <sys/un.h>
#include <sys/socket.h>
static int g_lock_fd = -1;

static int try_single_instance(void) {
    const char *path = "/tmp/void_term.lock";
    g_lock_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (g_lock_fd < 0) return 0;
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    unlink(path);
    if (bind(g_lock_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(g_lock_fd);
        g_lock_fd = -1;
        return 0; // Another instance holds the lock
    }
    listen(g_lock_fd, 1);
    return 1;
}

long hexa_appkit_init_term(long rows, long cols, long font_size) {
    capture_argv0_once();

    // Shadow mode: our parent is about to hand over control. Skip the
    // single-instance lock (parent still holds it, will release on exit),
    // adopt the inherited handoff socket, and read the state file.
    const char *shadow_env      = getenv("VOID_SHADOW");
    const char *handoff_path    = getenv("VOID_HANDOFF_PATH");
    const char *handoff_sock    = getenv("VOID_HANDOFF_SOCK");
    int is_shadow = (shadow_env && shadow_env[0] == '1');
    HandoffHeader restored_hdr = {0};
    if (is_shadow) {
        if (handoff_sock) g_shadow_sock = atoi(handoff_sock);
        if (handoff_path) {
            if (restore_handoff_from_file(handoff_path, &restored_hdr) != 0) {
                fprintf(stderr, "[void] shadow: handoff restore failed\n");
                return -1;
            }
            unlink(handoff_path); // one-shot
        }
    } else if (!try_single_instance()) {
        fprintf(stderr, "[void] already running\n");
        return -1;
    }
    // Load profile config (~/.void/profiles.json) — creates default if missing
    load_profiles();

    // Restore persisted layout mode (Cmd+G state) from NSUserDefaults so
    // the grid/stacked choice survives restarts.
    @autoreleasepool {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSInteger saved = [ud integerForKey:@"voidLayoutMode"];
        if (saved == LAYOUT_GRID) g_layout_mode = LAYOUT_GRID;
        else                      g_layout_mode = LAYOUT_STACKED;
        g_layout_dirty = 1;
    }
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        g_term_delegate = [[HexaTermDelegate alloc] init];
        [app setDelegate:g_term_delegate];

        // Match Terminal.app: SFMono-Regular 13pt (fallback chain).
        // The helper caches bold ONCE at startup. Creating it per-cell-
        // per-frame (CTFontCreateCopyWithSymbolicTraits) thrashes CGFont
        // cache and crashed Terminal.app via CGFontStrikeRelease → free_tiny.
        int fs = font_size > 0 ? (int)font_size : 13;
        set_font_size(fs);
        // Auto-size from screen (ignore passed rows/cols). In shadow
        // mode we reuse the restored rows/cols + window frame so the
        // user sees no geometry change across the swap.
        NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
        float ww, wh, wx, wy;
        if (is_shadow && restored_hdr.win_w > 0) {
            g_term_cols = restored_hdr.term_cols;
            g_term_rows = restored_hdr.term_rows;
            // grids already populated by restore_handoff_from_file; do
            // NOT reset g_term_grid (it holds the active tab's state).
            ww = restored_hdr.win_w;
            wh = restored_hdr.win_h;
            wx = restored_hdr.win_x;
            wy = restored_hdr.win_y;
        } else {
            ww = screenFrame.size.width * 0.85;
            wh = screenFrame.size.height * 0.85;
            int init_tbw = effective_tab_bar_w();
            g_term_cols = (int)((ww - init_tbw) / g_term_cw);
            g_term_rows = (int)(wh / g_term_ch);
            if (g_term_cols < 80) g_term_cols = 80;
            if (g_term_rows < 24) g_term_rows = 24;
            if (g_term_cols > TERM_MAX_COLS) g_term_cols = TERM_MAX_COLS;
            if (g_term_rows > TERM_MAX_ROWS) g_term_rows = TERM_MAX_ROWS;
            tab_clear_grid(g_term_grid);
            ww = init_tbw + g_term_cw * g_term_cols;
            wh = g_term_ch * g_term_rows;
            wx = screenFrame.origin.x + (screenFrame.size.width - ww) / 2;
            wy = screenFrame.origin.y + (screenFrame.size.height - wh) / 2;
        }
        NSRect frame = NSMakeRect(wx, wy, ww, wh);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        g_window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                                 backing:NSBackingStoreBuffered defer:NO];
        [g_window setTitle:@"VOID"];
        [g_window setDelegate:g_term_delegate];
        // Min size uses the worst-case tab bar width so the window stays
        // sane even when the user later creates a second tab.
        [g_window setMinSize:NSMakeSize(TAB_BAR_W + g_term_cw * 20, g_term_ch * 5)];
        if (@available(macOS 10.14, *))
            [g_window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [g_window setBackgroundColor:[NSColor blackColor]];

        NSView *tv = [[HexaTermView alloc] initWithFrame:frame];
        [g_window setContentView:tv];
        [g_window makeFirstResponder:tv];
        // Shadow process keeps its window off-screen until the parent
        // hands over (RDY/GO protocol). Everyone else shows it now.
        if (!is_shadow) {
            [g_window makeKeyAndOrderFront:nil];
        }

        // ── Menu bar ──
        // Full menu with File / Edit / View / Window so the user can
        // reach every action via the mouse. Each item targets
        // g_term_delegate so the menu dispatch ends up in the same
        // mutable globals that the Cmd-intercept path touches.
        NSMenu *mb = [[NSMenu alloc] init];
        [app setMainMenu:mb];
        id D = g_term_delegate;

        // Helper macro — adds a menu item with title, selector and
        // keyEquivalent (pass @"" for no shortcut). Key-equivalent
        // modifiers default to Cmd.
        #define MI(menu, title, sel, key) do { \
            NSMenuItem *_it = [[NSMenuItem alloc] initWithTitle:(title) \
                                                         action:(sel) \
                                                  keyEquivalent:(key)]; \
            [_it setTarget:D]; \
            [menu addItem:_it]; \
        } while (0)

        // Application menu (leftmost — shows the app name)
        {
            NSMenuItem *mi = [[NSMenuItem alloc] init];
            [mb addItem:mi];
            NSMenu *am = [[NSMenu alloc] initWithTitle:@"VOID"];
            [mi setSubmenu:am];
            [am addItemWithTitle:@"VOID 정보" action:nil keyEquivalent:@""];
            [am addItem:[NSMenuItem separatorItem]];
            NSMenuItem *hide = [[NSMenuItem alloc]
                initWithTitle:@"VOID 숨기기"
                       action:@selector(hide:)
                keyEquivalent:@"h"];
            [am addItem:hide];
            [am addItem:[NSMenuItem separatorItem]];
            [am addItemWithTitle:@"VOID 종료"
                          action:@selector(terminate:)
                   keyEquivalent:@"q"];
        }

        // File menu — tab lifecycle
        {
            NSMenuItem *mi = [[NSMenuItem alloc] init];
            [mb addItem:mi];
            NSMenu *fm = [[NSMenu alloc] initWithTitle:@"파일"];
            [mi setSubmenu:fm];
            MI(fm, @"새 탭",        @selector(menuNewTab:),     @"t");
            MI(fm, @"탭 닫기",      @selector(menuCloseTab:),   @"w");
            [fm addItem:[NSMenuItem separatorItem]];
            MI(fm, @"닫은 탭 다시 열기", @selector(menuUndoClose:), @"z");
        }

        // Edit menu — clipboard + search
        {
            NSMenuItem *mi = [[NSMenuItem alloc] init];
            [mb addItem:mi];
            NSMenu *em = [[NSMenu alloc] initWithTitle:@"편집"];
            [mi setSubmenu:em];
            MI(em, @"복사",         @selector(menuCopy:),       @"c");
            MI(em, @"붙여넣기",     @selector(menuPaste:),      @"v");
            [em addItem:[NSMenuItem separatorItem]];
            MI(em, @"찾기",         @selector(menuFind:),       @"f");
        }

        // View menu — layout + zoom
        {
            NSMenuItem *mi = [[NSMenuItem alloc] init];
            [mb addItem:mi];
            NSMenu *vm = [[NSMenu alloc] initWithTitle:@"보기"];
            [mi setSubmenu:vm];
            MI(vm, @"탭",           @selector(menuLayoutStacked:), @"");
            MI(vm, @"그리드",       @selector(menuLayoutGrid:),    @"g");
            [vm addItem:[NSMenuItem separatorItem]];
            MI(vm, @"다음 탭",      @selector(menuCycleNext:),     @"");
            [vm addItem:[NSMenuItem separatorItem]];
            MI(vm, @"확대",         @selector(menuZoomIn:),        @"=");
            MI(vm, @"축소",         @selector(menuZoomOut:),       @"-");
            MI(vm, @"원래 크기",    @selector(menuZoomReset:),     @"0");
        }

        // Window menu — macOS populates standard window items here
        {
            NSMenuItem *mi = [[NSMenuItem alloc] init];
            [mb addItem:mi];
            NSMenu *wm = [[NSMenu alloc] initWithTitle:@"윈도우"];
            [mi setSubmenu:wm];
            [wm addItemWithTitle:@"최소화"
                          action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
            [wm addItemWithTitle:@"확대/축소"
                          action:@selector(performZoom:)
                   keyEquivalent:@""];
            [app setWindowsMenu:wm];
        }

        #undef MI

        // App icon — monochrome "V" on a rounded-square plate.
        //
        // Follows Apple's official macOS Big Sur+ icon template:
        //   canvas       1024 × 1024
        //   plate        824 × 824, centered (exactly 100px gutter)
        //   corner r     185.4 (≈22.5% of 824) — the squircle shape
        //   content      inside the plate
        //
        // macOS does NOT apply rounded corners automatically on .app icons
        // (unlike iOS), so we fill a NSBezierPath manually. Palette stays
        // monochrome: charcoal plate + light-gray glyph, no color channels.
        {
            CGFloat S = 1024.0;         // full canvas
            CGFloat GUTTER = 100.0;     // Apple-official 100px gutter
            CGFloat PS = S - GUTTER * 2;   // plate size = 824
            CGFloat PR = 185.4;         // plate corner radius per template
            NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(S, S)];
            [icon lockFocus];

            // Transparent canvas so the Dock background shows through the
            // gutter — Apple icons "float" on the dock, they don't fill it.
            [[NSColor clearColor] set];
            NSRectFill(NSMakeRect(0, 0, S, S));

            // Centered 824×824 rounded-square plate — charcoal (not pure
            // black) so it reads on both light and dark Docks.
            NSRect plateRect = NSMakeRect(GUTTER, GUTTER, PS, PS);
            NSBezierPath *plate = [NSBezierPath
                bezierPathWithRoundedRect:plateRect
                                  xRadius:PR yRadius:PR];
            [[NSColor colorWithWhite:0.08 alpha:1.0] setFill];
            [plate fill];

            // Thin inner hairline for depth — still greyscale.
            NSBezierPath *inner = [NSBezierPath
                bezierPathWithRoundedRect:NSInsetRect(plateRect, 5, 5)
                                  xRadius:PR - 5 yRadius:PR - 5];
            [[NSColor colorWithWhite:0.14 alpha:1.0] setStroke];
            [inner setLineWidth:2.0];
            [inner stroke];

            // "V" glyph centered inside the plate, sized to fill ~60% of
            // the plate height — leaves optical breathing room inside the
            // rounded corners.
            NSFont *gfont = [NSFont boldSystemFontOfSize:PS * 0.62];
            NSDictionary *gattrs = @{
                NSFontAttributeName: gfont,
                NSForegroundColorAttributeName:
                    [NSColor colorWithWhite:0.78 alpha:1.0]
            };
            NSString *glyph = @"V";
            NSSize gs = [glyph sizeWithAttributes:gattrs];
            CGFloat gx = GUTTER + (PS - gs.width) / 2.0;
            CGFloat gy = GUTTER + (PS - gs.height) / 2.0 - PS * 0.02;
            [glyph drawAtPoint:NSMakePoint(gx, gy) withAttributes:gattrs];

            [icon unlockFocus];
            [app setApplicationIconImage:icon];
        }

        [app finishLaunching];
        if (!is_shadow)
            [app activateIgnoringOtherApps:YES];
    }

    // Install the swap signal so void-swap can trigger a seamless exec.
    // SIGUSR1 just sets a flag; the real work happens in the main loop.
    struct sigaction sa = {0};
    sa.sa_handler = handle_sigusr1;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);

    // Shadow handshake: tell parent we're ready, wait for go.
    if (is_shadow && g_shadow_sock >= 0) {
        write(g_shadow_sock, "RDY\n", 4);
        char buf[8];
        int n = (int)read(g_shadow_sock, buf, sizeof(buf));
        (void)n; // we simply block until parent writes "GO\n" (or closes)
        @autoreleasepool {
            [g_window makeKeyAndOrderFront:nil];
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        }
        close(g_shadow_sock);
        g_shadow_sock = -1;
    }
    return 0;
}

// ── Tab API for hexa ──

// Renumber profile-locked tabs that share a base name. Single sibling stays
// bare ("nexus"); two or more become "nexus (1)", "nexus (2)", … in tab order.
// Called after every open and close so closing "(2)" of three reflows the rest.
static void void_tabs_renumber_profiles(void) {
    for (int i = 0; i < g_num_tabs; i++) {
        if (!g_tabs[i].used) continue;
        if (!g_tabs[i].title_locked) continue;
        if (!g_tabs[i].profile_base[0]) continue;

        // Count siblings with the same profile_base.
        int total = 0;
        for (int j = 0; j < g_num_tabs; j++) {
            if (!g_tabs[j].used || !g_tabs[j].title_locked) continue;
            if (strcmp(g_tabs[j].profile_base, g_tabs[i].profile_base) == 0) total++;
        }

        if (total == 1) {
            snprintf(g_tabs[i].title, sizeof(g_tabs[i].title), "%s",
                     g_tabs[i].profile_base);
        } else {
            // i's rank among siblings (1-based, by tab order).
            int rank = 0;
            for (int j = 0; j <= i; j++) {
                if (!g_tabs[j].used || !g_tabs[j].title_locked) continue;
                if (strcmp(g_tabs[j].profile_base, g_tabs[i].profile_base) == 0) rank++;
            }
            snprintf(g_tabs[i].title, sizeof(g_tabs[i].title), "%s (%d)",
                     g_tabs[i].profile_base, rank);
        }
    }
}

// Move a tab from slot `from` to slot `to`, shifting the tabs in between.
// Used by the drag-reorder gesture. VoidTab is struct-copied, so pty_fd,
// grid, and scrollback section pointers travel with the tab — the shell
// keeps running on the same fd, only the array index changes. The active
// tab index is adjusted so the focus follows the moved tab if it was
// the one being dragged, or stays on the same logical tab otherwise.
static void tabs_move(int from, int to) {
    if (from == to) return;
    if (from < 0 || from >= g_num_tabs) return;
    if (to < 0 || to >= g_num_tabs) return;

    int prev_active = g_active_tab;
    VoidTab tmp = g_tabs[from];
    if (from < to) {
        for (int i = from; i < to; i++) g_tabs[i] = g_tabs[i + 1];
    } else {
        for (int i = from; i > to; i--) g_tabs[i] = g_tabs[i - 1];
    }
    g_tabs[to] = tmp;

    if (prev_active == from) {
        g_active_tab = to;
    } else if (from < to) {
        if (prev_active > from && prev_active <= to) g_active_tab = prev_active - 1;
    } else {
        if (prev_active < from && prev_active >= to) g_active_tab = prev_active + 1;
    }

    // Profile sibling numbering depends on tab order — e.g. dragging
    // "nexus (2)" above "nexus (1)" should reassign the ranks.
    void_tabs_renumber_profiles();
    g_full_redraw = 1;
}

// Replace a tab's PTY with a fresh (profile-driven or plain) shell in
// place. Caller decides eligibility — this helper just does the swap:
// kill existing PTY, spawn new one, update title/profile metadata,
// reset grid + hexa VT state, full redraw. Used by Cmd+Ctrl+N when
// the window holds only one unprofiled tab (the "placeholder" slot).
static int tab_become_profile(int idx, VoidProfile *vp) {
    if (idx < 0 || idx >= g_num_tabs) return -1;
    if (!g_tabs[idx].used) return -1;

    // The initial blank tab owns a real (idle) shell PTY — reap it so
    // we don't leak a zombie sh process when the profile takes over.
    if (g_tabs[idx].pty_fd >= 0) {
        close(g_tabs[idx].pty_fd);
        g_tabs[idx].pty_fd = -1;
    }
    if (g_tabs[idx].pid > 0) {
        kill(g_tabs[idx].pid, SIGTERM);
        waitpid(g_tabs[idx].pid, NULL, WNOHANG);
        g_tabs[idx].pid = 0;
    }

    int fd = tab_spawn_pty_profile(vp);
    if (fd < 0) return -1;

    g_tabs[idx].pty_fd = fd;
    g_tabs[idx].pid = 0;
    g_tabs[idx].is_blank = 0;

    // Size the PTY to the current grid.
    struct winsize ws;
    ws.ws_row = (unsigned short)g_term_rows;
    ws.ws_col = (unsigned short)g_term_cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    ioctl(fd, TIOCSWINSZ, &ws);

    // Title / profile metadata (mirrors the hexa_tab_new logic).
    g_tabs[idx].title_locked = 0;
    g_tabs[idx].profile_base[0] = 0;
    if (vp && vp->title[0]) {
        snprintf(g_tabs[idx].profile_base, sizeof(g_tabs[idx].profile_base),
                 "%s", vp->title);
        snprintf(g_tabs[idx].title, sizeof(g_tabs[idx].title), "%s", vp->title);
        g_tabs[idx].title_locked = 1;
        snprintf(g_tabs[idx].cwd, sizeof(g_tabs[idx].cwd), "%s", vp->path);
    } else {
        g_tabs[idx].title[0] = 0;
        g_tabs[idx].cwd[0] = 0;
    }

    void_tabs_renumber_profiles();
    // Clear the rendering grid and force hexa to rebuild its VT screen
    // buffer. Without this the newly-spawned shell draws on top of the
    // blank state that hexa's scr buffer still holds, producing ghost
    // overlays like "top table at 80 cols, bottom at full width".
    tab_clear_grid(g_term_grid);
    g_term_cur_row = 0;
    g_term_cur_col = 0;
    g_resized = 1;        // triggers scr_init + vt_reset_state + pty_resize
    g_full_redraw = 1;
    return 0;
}

// Create a new tab. Spawns PTY, returns tab index (or -1).
// Special case: the very first call (before any tab exists) with no
// pending profile produces a BLANK tab — no PTY, no shell, black screen.
// The user picks a profile via Cmd+Ctrl+N which then converts the blank
// in place via tab_become_profile, so the app opens with zero clutter.
long hexa_tab_new(void) {
    // Shadow restore swallow: after a hot-swap the parent already
    // wrote the restored tabs into g_tabs[], and hexa's main() still
    // calls hexa_tab_new() once for the "initial" tab. We return the
    // restored active tab without spawning anything. Subsequent calls
    // (Cmd+T, profile shortcuts) take the normal path.
    static int g_shadow_restore_swallowed = 0;
    if (g_shadow_restored && !g_shadow_restore_swallowed) {
        g_shadow_restore_swallowed = 1;
        // Signal hexa to reload its VT state from the restored grid.
        g_resized = 1;
        g_full_redraw = 1;
        return (long)(g_active_tab >= 0 ? g_active_tab : 0);
    }

    if (g_num_tabs >= MAX_TABS) return -1;

    // Save current active tab's grid
    if (g_active_tab >= 0 && g_active_tab < g_num_tabs) {
        memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
        g_tabs[g_active_tab].cur_row = g_term_cur_row;
        g_tabs[g_active_tab].cur_col = g_term_cur_col;
    }

    // Pending profile? Set by Cmd+Ctrl+N intercept.
    extern VoidProfile *g_pending_profile;
    VoidProfile *vp = g_pending_profile;
    g_pending_profile = NULL;

    // Blank-initial rule: the first tab is always a real working shell
    // (so ssh/git/etc. are immediately usable) but flagged is_blank so
    // a profile shortcut can convert it in place — UNTIL the user types
    // anything. The is_blank flag is cleared by hexa_keys_to_pty the
    // moment the first keystroke flows to the PTY.
    static int g_initial_tab_done = 0;
    int make_blank = (!g_initial_tab_done && !vp);
    g_initial_tab_done = 1;

    int idx = g_num_tabs;
    // Route through void-server when enabled — the daemon owns the PTY
    // master so the session survives void_term exit and hot-swap. Falls
    // back to direct fork-pty on server failure so the UI never breaks.
    int fd = -1;
    char new_session_id[32] = {0};
    if (void_server_enabled()) {
        const char *t = (vp && vp->title[0]) ? vp->title : "session";
        const char *p = (vp && vp->path[0])  ? vp->path  : (getenv("HOME") ?: "");
        const char *c = (vp && vp->cmd[0])   ? vp->cmd   : "";
        if (void_server_spawn(t, p, c, g_term_rows, g_term_cols,
                              new_session_id, &fd) != 0) {
            fd = -1;
        }
    }
    if (fd < 0) {
        fd = tab_spawn_pty_profile(vp);
    }
    if (fd < 0) return -1;

    g_tabs[idx].used = 1;
    g_tabs[idx].pty_fd = fd;
    g_tabs[idx].pid = 0;
    g_tabs[idx].is_blank = make_blank ? 1 : 0;
    memcpy(g_tabs[idx].session_id, new_session_id, 32);

    // Set PTY to actual window size immediately
    struct winsize ws;
    ws.ws_row = (unsigned short)g_term_rows;
    ws.ws_col = (unsigned short)g_term_cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    ioctl(fd, TIOCSWINSZ, &ws);

    // Title: profile tabs are renumbered as a group by void_tabs_renumber_profiles.
    // 1 sibling → "nexus", 2+ siblings → "nexus (1)", "nexus (2)", … in tab order.
    // Title is locked so OSC 0 from the shell can't overwrite it.
    g_tabs[idx].title_locked = 0;
    g_tabs[idx].profile_base[0] = 0;
    if (vp && vp->title[0]) {
        snprintf(g_tabs[idx].profile_base, sizeof(g_tabs[idx].profile_base),
                 "%s", vp->title);
        snprintf(g_tabs[idx].title, sizeof(g_tabs[idx].title), "%s", vp->title);
        g_tabs[idx].title_locked = 1;
        // Remember cwd so OSC 7 path-completion has a starting point
        snprintf(g_tabs[idx].cwd, sizeof(g_tabs[idx].cwd), "%s", vp->path);
    } else {
        snprintf(g_tabs[idx].title, sizeof(g_tabs[idx].title), "");
        g_tabs[idx].cwd[0] = 0;
    }
    tab_clear_grid(g_tabs[idx].grid);
    g_tabs[idx].cur_row = 0;
    g_tabs[idx].cur_col = 0;
    for (int s = 0; s < SB_MAX_SECTIONS; s++) {
        g_tabs[idx].sb[s].cells = NULL;
        g_tabs[idx].sb[s].lines = 0;
    }
    g_tabs[idx].sb_head = 0;
    g_tabs[idx].sb_num = 0;
    g_tabs[idx].sb_total = 0;
    g_tabs[idx].has_alarm = 0;

    g_num_tabs++;
    g_active_tab = idx;

    // Mirror the current shared rows/cols into the new tab's tile
    // dims so apply_grid_layout (on the next tick) has a sane baseline.
    g_tabs[idx].tile_rows = g_term_rows;
    g_tabs[idx].tile_cols = g_term_cols;
    g_tabs[idx].bg_cur_row = 0;
    g_tabs[idx].bg_cur_col = 0;
    g_tabs[idx].bg_esc_state = 0;

    // Renumber profile group now that the new sibling is in place.
    void_tabs_renumber_profiles();

    // Cmd+Z position restore — if tab_reopen_last set a target slot,
    // shift the freshly-created tab from the end into that slot so the
    // reopened tab lands exactly where it was closed.
    if (g_reopen_target_idx >= 0 &&
        g_reopen_target_idx < g_num_tabs - 1) {
        tabs_move(g_num_tabs - 1, g_reopen_target_idx);
    }
    g_reopen_target_idx = -1;

    // Clear active rendering grid for new tab
    tab_clear_grid(g_term_grid);
    g_term_cur_row = 0;
    g_term_cur_col = 0;
    g_full_redraw = 1;

    // Grid mode: tab count just changed, so every tile needs to shrink.
    // Force a reflow on the next poll tick.
    if (g_layout_mode == LAYOUT_GRID) {
        g_layout_dirty = 1;
        g_eff_tab_bar_w_cache = -1;
    }

    return (long)idx;
}

// Global used to hand a profile from the Cmd+Ctrl+N intercept to
// hexa_tab_new (called on the hexa main-loop tick). Only valid
// for the single new-tab request immediately following the keypress.
VoidProfile *g_pending_profile = NULL;

// Close a tab. For server-backed sessions (session_id[0] != 0) this
// sends DETACH so the server keeps the shell alive for later reattach;
// the local PTY fd is closed but the kernel refcount stays nonzero
// because the server holds its own copy of the fd. For direct-spawn
// tabs the PTY is killed like before.
long hexa_tab_close(long idx) {
    if (idx < 0 || idx >= g_num_tabs) return g_active_tab;
    if (!g_tabs[idx].used) return g_active_tab;

    // Push a snapshot onto the undo-close stack so Cmd+Z can respawn
    // the same profile. We only save identity (title + profile_base +
    // cwd + original_idx), not live shell state.
    {
        if (g_closed_count >= CLOSED_STACK_MAX) {
            for (int k = 1; k < CLOSED_STACK_MAX; k++)
                g_closed_stack[k - 1] = g_closed_stack[k];
            g_closed_count = CLOSED_STACK_MAX - 1;
        }
        ClosedTabSnapshot *snap = &g_closed_stack[g_closed_count++];
        memset(snap, 0, sizeof(*snap));
        snprintf(snap->title,        sizeof(snap->title),
                 "%s", g_tabs[idx].title);
        snprintf(snap->profile_base, sizeof(snap->profile_base),
                 "%s", g_tabs[idx].profile_base);
        snprintf(snap->cwd,          sizeof(snap->cwd),
                 "%s", g_tabs[idx].cwd);
        snap->was_profile = g_tabs[idx].profile_base[0] ? 1 : 0;
        snap->original_idx = (int)idx;
    }

    // Server-backed? → DETACH (session survives on server side) and
    // close the local fd without killing the shell. The server still
    // holds its own copy of the PTY master so the kernel refcount
    // doesn't drop to zero and no SIGHUP fires on the slave.
    int server_backed = (g_tabs[idx].session_id[0] != 0);
    if (server_backed) {
        void_server_detach(g_tabs[idx].session_id);
        if (g_tabs[idx].pty_fd >= 0) {
            close(g_tabs[idx].pty_fd);
            g_tabs[idx].pty_fd = -1;
        }
        // Do NOT kill pid — the server owns the shell process now.
        g_tabs[idx].pid = 0;
        goto close_bookkeeping;
    }

    // Kill PTY
    if (g_tabs[idx].pty_fd >= 0) {
        close(g_tabs[idx].pty_fd);
        g_tabs[idx].pty_fd = -1;
    }
    if (g_tabs[idx].pid > 0) {
        kill(g_tabs[idx].pid, SIGTERM);
        waitpid(g_tabs[idx].pid, NULL, WNOHANG);
    }

close_bookkeeping:
    g_tabs[idx].used = 0;
    g_tabs[idx].session_id[0] = 0;

    // Free scrollback sections before shift
    for (int s = 0; s < SB_MAX_SECTIONS; s++) {
        if (g_tabs[idx].sb[s].cells) {
            free(g_tabs[idx].sb[s].cells);
            g_tabs[idx].sb[s].cells = NULL;
            g_tabs[idx].sb[s].lines = 0;
        }
    }
    g_tabs[idx].sb_head = 0;
    g_tabs[idx].sb_num = 0;
    g_tabs[idx].sb_total = 0;

    // Shift tabs down
    for (int i = (int)idx; i < g_num_tabs - 1; i++) {
        g_tabs[i] = g_tabs[i + 1];
    }
    g_num_tabs--;
    // NULL dead slot to prevent double-free (shift copied pointers).
    if (g_num_tabs < MAX_TABS) {
        for (int s = 0; s < SB_MAX_SECTIONS; s++) {
            g_tabs[g_num_tabs].sb[s].cells = NULL;
            g_tabs[g_num_tabs].sb[s].lines = 0;
        }
        g_tabs[g_num_tabs].sb_head = 0;
        g_tabs[g_num_tabs].sb_num = 0;
        g_tabs[g_num_tabs].sb_total = 0;
    }
    g_scroll_offset = 0;
    g_full_redraw = 1;

    if (g_num_tabs == 0) {
        g_active_tab = -1;
        return -1;
    }

    // Renumber surviving profile siblings: closing "(2)" of three becomes
    // "(1)", "(2)" again; closing one of two collapses the survivor to bare.
    void_tabs_renumber_profiles();

    // Adjust active tab
    if (g_active_tab >= g_num_tabs) g_active_tab = g_num_tabs - 1;
    if (g_active_tab == (int)idx && g_active_tab > 0) g_active_tab--;

    // Load new active tab's grid
    memcpy(g_term_grid, g_tabs[g_active_tab].grid, sizeof(g_term_grid));
    g_term_cur_row = g_tabs[g_active_tab].cur_row;
    g_term_cur_col = g_tabs[g_active_tab].cur_col;

    // Grid mode: tab count changed → remaining tiles need to expand.
    // Marking layout dirty triggers apply_grid_layout on the next tick.
    // If we dropped below 1 tab we already returned above.
    if (g_layout_mode == LAYOUT_GRID) {
        g_layout_dirty = 1;
        g_eff_tab_bar_w_cache = -1;
    }

    return (long)g_active_tab;
}

// Get active tab's PTY fd. Returns -1 if no active tab.
long hexa_tab_get_pty(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return -1;
    return (long)g_tabs[g_active_tab].pty_fd;
}

// Poll for tab commands: 0=none, 1=new, 2=close, 3=switched
long hexa_tab_poll_cmd(void) {
    long cmd = g_tab_cmd;
    g_tab_cmd = 0;
    return cmd;
}

// Get active tab index
long hexa_tab_get_active(void) {
    return (long)g_active_tab;
}

// Get number of tabs
long hexa_tab_count(void) {
    return (long)g_num_tabs;
}

// Load a cell from C's active rendering grid (for hexa screen reload after tab switch)
long hexa_tab_cell_cp(long idx) {
    int r = (int)idx / g_term_cols, c = (int)idx % g_term_cols;
    if (r < 0 || r >= TERM_MAX_ROWS || c < 0 || c >= TERM_MAX_COLS) return 32;
    return (long)g_term_grid[r][c].ch;
}
long hexa_tab_cell_fg(long idx) {
    int r = (int)idx / g_term_cols, c = (int)idx % g_term_cols;
    if (r < 0 || r >= TERM_MAX_ROWS || c < 0 || c >= TERM_MAX_COLS) return 7;
    return (long)g_term_grid[r][c].fg;
}
long hexa_tab_cell_bg(long idx) {
    int r = (int)idx / g_term_cols, c = (int)idx % g_term_cols;
    if (r < 0 || r >= TERM_MAX_ROWS || c < 0 || c >= TERM_MAX_COLS) return 0;
    return (long)g_term_grid[r][c].bg;
}
long hexa_tab_cell_flags(long idx) {
    int r = (int)idx / g_term_cols, c = (int)idx % g_term_cols;
    if (r < 0 || r >= TERM_MAX_ROWS || c < 0 || c >= TERM_MAX_COLS) return 0;
    return (long)g_term_grid[r][c].flags;
}
long hexa_tab_cursor_x(void) { return (long)g_term_cur_col; }
long hexa_tab_cursor_y(void) { return (long)g_term_cur_row; }

// Set tab title (from hexa OSC parse)
void hexa_tab_set_title(long tab_idx, long byte_val) {
    // Append byte to tab title (reset on first call after switch)
    // Simple: just pass whole title via the existing title_buf mechanism
}

// NOTE: parameter types MUST match hexa's extern prototype (int, not long).
// hexa emits a C declaration with 32-bit int; if we use long here the ARM64
// ABI sees 64-bit registers and the upper halves are garbage — the flags
// in particular (0x10000 wide-head, 0x20000 continuation) would not round-trip.
void hexa_appkit_term_set_cell(int row, int col, int ch, int fg, int bg, int flags) {
    if (row < 0 || row >= TERM_MAX_ROWS || col < 0 || col >= TERM_MAX_COLS) return;
    TermCell *cp = &g_term_grid[row][col];
    // Equal-cell early exit: hexa's sync_to_bridge writes the whole grid every
    // frame; this cuts ~90% of writes for typing workloads.
    if (cp->ch == (unichar)ch && cp->fg == fg &&
        cp->bg == bg && cp->flags == flags) return;
    cp->ch = (unichar)ch;
    cp->fg = fg;
    cp->bg = bg;
    cp->flags = flags;
    // Mark dirty range
    if (g_dirty_min < 0 || row < g_dirty_min) g_dirty_min = row;
    if (row > g_dirty_max) g_dirty_max = row;
}

void hexa_appkit_term_set_cursor(long row, long col, long vis) {
    // Cursor move dirties both the old and new row
    if (g_prev_cur_row != (int)row || g_prev_cur_col != (int)col ||
        g_term_cur_row != (int)row || g_term_cur_col != (int)col) {
        int r0 = g_term_cur_row, r1 = (int)row;
        if (r0 > r1) { int t = r0; r0 = r1; r1 = t; }
        if (g_dirty_min < 0 || r0 < g_dirty_min) g_dirty_min = r0;
        if (r1 > g_dirty_max) g_dirty_max = r1;
    }
    g_prev_cur_row = g_term_cur_row;
    g_prev_cur_col = g_term_cur_col;
    g_term_cur_row = (int)row;
    g_term_cur_col = (int)col;
    g_term_cur_vis = (int)vis;
}

// Request a full redraw on next flush. Called from tab switch, resize, init.
void hexa_appkit_term_invalidate_all(void) {
    g_full_redraw = 1;
}

// Parent-side hot swap. Spawns a shadow child that re-execs the current
// binary with VOID_SHADOW=1, waits for the child's "RDY", hides our
// window, writes "GO", and exits. PTY fds survive fork+execv because we
// clear FD_CLOEXEC on them first, so the claude/shell subprocesses
// continue running uninterrupted — the shadow adopts the same integer
// fd numbers from the handoff file.
static void perform_hot_swap(void) {
    capture_argv0_once();
    if (!g_argv0[0]) return;

    char path[256];
    snprintf(path, sizeof(path), "/tmp/void_handoff_%d.bin", (int)getpid());
    if (save_handoff_to_file(path) != 0) {
        fprintf(stderr, "[void] swap: save failed\n");
        return;
    }

    // Clear FD_CLOEXEC on every live PTY fd so they survive the execv
    // in the child. The child will adopt the same integer fd numbers
    // via the handoff file, so the kernel keeps the refcounts right.
    for (int i = 0; i < g_num_tabs; i++) {
        if (g_tabs[i].used && g_tabs[i].pty_fd >= 0)
            handoff_keep_fd(g_tabs[i].pty_fd);
    }
    // Single-instance lock fd also needs to travel (or be reopened
    // later) — simplest is to let the shadow skip the check.

    int sp[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp) != 0) {
        fprintf(stderr, "[void] swap: socketpair failed\n");
        unlink(path);
        return;
    }
    // Both ends of sp need to be inheritable across execv so the child's
    // new image can find its end via an env var.
    handoff_keep_fd(sp[0]);
    handoff_keep_fd(sp[1]);

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "[void] swap: fork failed\n");
        close(sp[0]); close(sp[1]);
        unlink(path);
        return;
    }
    if (pid == 0) {
        // Child: exec the new binary with swap env wired up.
        close(sp[0]); // parent's end
        char sock_env[32];
        snprintf(sock_env, sizeof(sock_env), "%d", sp[1]);
        setenv("VOID_SHADOW",       "1",       1);
        setenv("VOID_HANDOFF_PATH", path,      1);
        setenv("VOID_HANDOFF_SOCK", sock_env,  1);
        // argv[0] only — hexa's main doesn't consume any flags and we
        // don't want --test or similar to bleed through.
        char *new_argv[] = { g_argv0, NULL };
        execv(g_argv0, new_argv);
        // If we reach here, exec failed.
        fprintf(stderr, "[void] swap: execv failed: %s\n", g_argv0);
        _exit(127);
    }

    // Parent: wait for shadow to finish init and signal ready.
    close(sp[1]);
    char buf[16] = {0};
    int n = (int)read(sp[0], buf, sizeof(buf) - 1);
    if (n <= 0 || buf[0] != 'R') {
        fprintf(stderr, "[void] swap: shadow never signalled RDY\n");
        close(sp[0]);
        return; // abort; parent keeps running
    }

    // Hide our window first (Cocoa defers until next runloop tick, but
    // that's fine — we write "GO" immediately and exit).
    @autoreleasepool {
        if (g_window) {
            [g_window orderOut:nil];
            [g_window setReleasedWhenClosed:NO];
        }
    }
    write(sp[0], "GO\n", 3);
    close(sp[0]);

    // Give Cocoa a few ms to actually drop our window before we exit —
    // otherwise the dock sees both our window and the shadow's and the
    // menu bar flickers between them.
    usleep(30 * 1000);
    _exit(0);
}

// ── Clipboard helpers (copy / paste) ─────────────────────────────────
// selection_build_text builds a UTF-8 NSString from the currently
// selected cell range; if no selection is active it falls back to the
// whole visible grid (matches macOS Terminal.app's "Edit → Select All"
// via Cmd+A behavior, but we trigger it implicitly on empty-Cmd+C).
// copy_selection_to_clipboard writes that text to the general pasteboard.
// paste_from_clipboard reads the pasteboard and writes UTF-8 bytes
// directly into the active tab's PTY wrapped with bracketed-paste
// markers so programs like zsh/bash/vim see it as a single block.

static NSString *selection_build_text(void) {
    int sr, sc, er, ec;
    int have_sel = normalize_selection(&sr, &sc, &er, &ec);
    int full_copy = 0;
    if (!have_sel) {
        // Empty selection → copy the whole visible grid.
        if (g_term_rows <= 0 || g_term_cols <= 0) return @"";
        sr = 0; sc = 0;
        er = g_term_rows - 1;
        ec = g_term_cols - 1;
        full_copy = 1;
    }

    NSMutableString *out = [NSMutableString stringWithCapacity:256];
    for (int r = sr; r <= er && r < g_term_rows; r++) {
        int c0 = (r == sr && !full_copy) ? sc : 0;
        int c1 = (r == er && !full_copy) ? ec : (g_term_cols - 1);
        if (c0 < 0) c0 = 0;
        if (c1 >= g_term_cols) c1 = g_term_cols - 1;

        // Gather cells into a temp row buffer so we can trim trailing
        // spaces cleanly. Width up to TERM_MAX_COLS.
        unichar rowbuf[TERM_MAX_COLS];
        int rowlen = 0;
        for (int c = c0; c <= c1; c++) {
            TermCell *cell = &g_term_grid[r][c];
            // Wide-char continuation slot — glyph was already emitted
            // by the head cell one column earlier.
            if (cell->flags & 0x20000) continue;
            unichar ch = cell->ch;
            // 0 bytes from never-written cells should appear as spaces
            // so trailing trim still works consistently.
            if (ch == 0) ch = ' ';
            if (rowlen < TERM_MAX_COLS) rowbuf[rowlen++] = ch;
        }
        // Trim trailing spaces — terminals pad rows with spaces for
        // cursor positioning but users don't want them in the paste.
        while (rowlen > 0 && (rowbuf[rowlen - 1] == ' ' || rowbuf[rowlen - 1] == 0))
            rowlen--;
        if (rowlen > 0) {
            NSString *line = [[NSString alloc] initWithCharacters:rowbuf length:rowlen];
            [out appendString:line];
            [line release];
        }
        // Row separator — skip after the final row so the pasted
        // text doesn't end with a spurious newline.
        if (r < er) [out appendString:@"\n"];
    }
    return out;
}

static void copy_selection_to_clipboard(void) {
    @autoreleasepool {
        NSString *s = selection_build_text();
        if (!s || s.length == 0) return;
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:s forType:NSPasteboardTypeString];
    }
}

static void paste_from_clipboard(void) {
    @autoreleasepool {
        if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return;
        VoidTab *tab = &g_tabs[g_active_tab];
        if (!tab->used || tab->pty_fd < 0) return;

        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        NSString *s = [pb stringForType:NSPasteboardTypeString];
        if (!s || s.length == 0) return;

        const char *utf8 = [s UTF8String];
        if (!utf8) return;
        size_t n = strlen(utf8);
        if (n == 0) return;

        // Bracketed paste — modern shells (zsh, bash, vim, nano) treat
        // `\x1b[200~ ... \x1b[201~` as a single pasted block so the
        // user's autoindent/smartindent/quotes don't mangle it. Shells
        // that haven't enabled the mode will print the ESC sequences
        // literally — acceptable tradeoff since DEC escape query is
        // far more intrusive than a one-line oddity on legacy shells.
        static const char START[] = "\x1b[200~";
        static const char END[]   = "\x1b[201~";
        (void)write(tab->pty_fd, START, sizeof(START) - 1);
        size_t off = 0;
        while (off < n) {
            ssize_t w = write(tab->pty_fd, utf8 + off, n - off);
            if (w <= 0) break;
            off += (size_t)w;
        }
        (void)write(tab->pty_fd, END, sizeof(END) - 1);
    }
}

void hexa_appkit_term_flush(void) {
    @autoreleasepool {
        NSView *v = [g_window contentView];
        if (!v) return;
        if (g_full_redraw || g_scroll_offset > 0 || g_search_active) {
            // Tab switch, resize, scrollback view, or active search
            // overlay — redraw everything. Overlay needs the full rect
            // so match highlights repaint against shifted cells when
            // PTY output scrolls the backing buffer.
            [v setNeedsDisplay:YES];
            g_full_redraw = 0;
            g_dirty_min = -1;
            g_dirty_max = -1;
            return;
        }
        if (g_dirty_min < 0) return; // nothing dirty
        // Convert dirty row range → minimal setNeedsDisplayInRect.
        // Expand by 1 row on each side to catch partial glyph overhang.
        int r0 = g_dirty_min - 1; if (r0 < 0) r0 = 0;
        int r1 = g_dirty_max + 1; if (r1 >= g_term_rows) r1 = g_term_rows - 1;
        int eff_tbw = effective_tab_bar_w();
        NSRect rect = NSMakeRect(eff_tbw,
                                  r0 * g_term_ch,
                                  [v bounds].size.width - eff_tbw,
                                  (r1 - r0 + 1) * g_term_ch);
        [v setNeedsDisplayInRect:rect];
        // Tab bar also needs repaint if title changed — cheap, do always
        if (eff_tbw > 0)
            [v setNeedsDisplayInRect:NSMakeRect(0, 0, eff_tbw, [v bounds].size.height)];
        g_dirty_min = -1;
        g_dirty_max = -1;
    }
}

static int g_resized = 0;

long hexa_appkit_term_poll(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        while (1) {
            NSEvent *ev = [app nextEventMatchingMask:NSEventMaskAny
                                           untilDate:nil
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES];
            if (!ev) break;

            // Intercept Cmd+key BEFORE sendEvent: — prevents macOS
            // menu/system from stealing Cmd+T/W/Q/1~9/Cmd+Ctrl+1~9.
            if ([ev type] == NSEventTypeKeyDown) {
                NSEventModifierFlags mods = [ev modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
                if (mods & NSEventModifierFlagCommand) {
                    NSString *raw = [ev charactersIgnoringModifiers];
                    if (raw.length > 0) {
                        unichar ch = [raw characterAtIndex:0];
                        int with_ctrl = (mods & NSEventModifierFlagControl) != 0;

                        // Cmd+Ctrl+0~9 → profile-based new tab (10 slots).
                        // Replace rule: if the window currently holds a
                        // single tab that hasn't been bound to a profile
                        // yet, a profile shortcut REPLACES that tab in
                        // place — no matter what the user typed in the
                        // plain shell. This is the "placeholder until
                        // you commit" model: one unprofiled tab serves
                        // as a scratchpad until you pick a workspace.
                        // Once profile_base is set (or tab count > 1),
                        // the shortcut always opens a new sibling.
                        if (with_ctrl && ch >= '0' && ch <= '9') {
                            VoidProfile *vp = profile_by_key((char)ch);
                            if (vp) {
                                int replace =
                                    (g_num_tabs == 1 &&
                                     g_active_tab == 0 &&
                                     g_tabs[0].profile_base[0] == 0);
                                if (replace &&
                                    tab_become_profile(0, vp) == 0) {
                                    g_tab_cmd = 3; // hexa reload screen
                                    clear_active_alarm();
                                    if (g_window)
                                        [[g_window contentView] setNeedsDisplay:YES];
                                } else {
                                    g_pending_profile = vp;
                                    g_tab_cmd = 1; // new tab signal to hexa
                                }
                            }
                            continue;
                        }

                        // Cmd+= / Cmd++ / Cmd+- / Cmd+0 → font zoom.
                        // charactersIgnoringModifiers returns '=' for
                        // Shift+= ('+'), so we test plain ASCII '='/'+'.
                        // This branch REPLACES the prior Cmd+0 → tab-10
                        // binding; to reach tab 10 use the Window menu
                        // or a mouse click on the tab bar instead.
                        if (!with_ctrl && (ch == '=' || ch == '+' ||
                                           ch == '-' || ch == '0')) {
                            int new_sz = g_font_size;
                            if (ch == '=' || ch == '+') new_sz++;
                            else if (ch == '-')         new_sz--;
                            else /* ch == '0' */        new_sz = 13;
                            if (new_sz < 8)  new_sz = 8;
                            if (new_sz > 40) new_sz = 40;
                            if (new_sz != g_font_size) {
                                set_font_size(new_sz);
                                // Force the resize path on the next loop
                                // tick: main loop recomputes cols/rows
                                // from the window frame ÷ new cw/ch,
                                // flags g_resized so hexa re-inits its
                                // scrollback, and TIOCSWINSZ fans out
                                // to every active PTY. Invalidating the
                                // tab-bar cache below guarantees the
                                // reflow branch fires even when the
                                // rounded cols/rows happen to match.
                                g_eff_tab_bar_w_cache = -1;
                                g_resized = 1;
                                g_full_redraw = 1;
                                if (g_window)
                                    [[g_window contentView] setNeedsDisplay:YES];
                            }
                            continue;
                        }

                        if (ch >= 'A' && ch <= 'Z') ch += 32; // tolower
                        if (ch == 't') {
                            // Cmd+T always opens a new shell tab —
                            // unlike the profile shortcut, there's no
                            // replace semantics for a plain shell
                            // since the user already has one.
                            if (0) {
                                g_tab_cmd = 3;
                                clear_active_alarm();
                                if (g_window)
                                    [[g_window contentView] setNeedsDisplay:YES];
                            } else {
                                g_tab_cmd = 1;
                            }
                            continue;
                        }
                        if (ch == 'w') { g_tab_cmd = 2; continue; }
                        if (ch == 'q') { g_term_quit = 1; continue; }
                        // Cmd+Z → undo the most recent tab close.
                        if (ch == 'z' && !(mods & NSEventModifierFlagShift)) {
                            tab_reopen_last();
                            continue;
                        }
                        // Cmd+C / Cmd+V clipboard. Ctrl+C stays SIGINT.
                        if (ch == 'c' && !with_ctrl) {
                            copy_selection_to_clipboard();
                            continue;
                        }
                        if (ch == 'v' && !with_ctrl) {
                            paste_from_clipboard();
                            if (g_scroll_offset > 0) {
                                g_scroll_offset = 0;
                                g_full_redraw = 1;
                            }
                            clear_selection();
                            if (g_window)
                                [[g_window contentView] setNeedsDisplay:YES];
                            continue;
                        }
                        // Cmd+F → toggle scrollback search overlay.
                        if (ch == 'f' && !with_ctrl) {
                            if (g_search_active) search_close();
                            else                 search_open();
                            if (g_window)
                                [[g_window contentView] setNeedsDisplay:YES];
                            continue;
                        }
                        // Cmd+G → toggle tiling grid layout.
                        if (ch == 'g') {
                            if (g_num_tabs >= 1 && g_num_tabs <= 9)
                                g_layout_mode = (g_layout_mode == LAYOUT_GRID)
                                    ? LAYOUT_STACKED : LAYOUT_GRID;
                            else
                                g_layout_mode = LAYOUT_STACKED;
                            g_layout_dirty = 1;
                            g_full_redraw = 1;
                            g_eff_tab_bar_w_cache = -1;
                            if (g_window)
                                [[g_window contentView] setNeedsDisplay:YES];
                            continue;
                        }
                        // Cmd+1~9 → tab 1..9. Cmd+0 is handled above as
                        // font-reset, so tab 10 has no keyboard shortcut.
                        int target = -1;
                        if (ch >= '1' && ch <= '9') target = ch - '1';
                        if (target >= 0) {
                            if (target < g_num_tabs && target != g_active_tab) {
                                if (g_active_tab >= 0 && g_active_tab < MAX_TABS) {
                                    memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
                                    g_tabs[g_active_tab].cur_row = g_term_cur_row;
                                    g_tabs[g_active_tab].cur_col = g_term_cur_col;
                                }
                                g_active_tab = target;
                                memcpy(g_term_grid, g_tabs[target].grid, sizeof(g_term_grid));
                                g_term_cur_row = g_tabs[target].cur_row;
                                g_term_cur_col = g_tabs[target].cur_col;
                                g_scroll_offset = 0;
                                g_tab_cmd = 3;
                                g_full_redraw = 1;
                                clear_active_alarm();
                                if (g_window)
                                    [[g_window contentView] setNeedsDisplay:YES];
                            }
                            continue;
                        }
                    }
                    continue; // swallow unknown Cmd combos
                }
            }

            [app sendEvent:ev];
            [app updateWindows];
        }
        // Check for window resize — and also for tab-bar-width transitions
        // (1↔2 tab count). Reflow on either trigger so the terminal grid
        // grows into the vacated pixels or shrinks to make room for the
        // freshly-revealed tab bar.
        if (g_window && g_term_cw > 0 && g_term_ch > 0) {
            NSRect f = [[g_window contentView] frame];
            int eff_tbw = effective_tab_bar_w();
            int in_grid = (g_layout_mode == LAYOUT_GRID && g_num_tabs >= 1 && g_num_tabs <= 9);
            int grid_needs_reflow = (in_grid && g_layout_dirty);
            int tbw_changed = (eff_tbw != g_eff_tab_bar_w_cache);

            if (in_grid) {
                // Grid mode: detect a window size change by cached dims
                // instead of comparing against g_term_cols/rows (those get
                // overwritten to the active tile's size below, so a tick-
                // to-tick comparison with the full window width would
                // trigger an endless reflow loop).
                static float s_last_w = -1, s_last_h = -1;
                int wh_changed = (f.size.width != s_last_w ||
                                  f.size.height != s_last_h);
                if (wh_changed || grid_needs_reflow || tbw_changed) {
                    s_last_w = f.size.width;
                    s_last_h = f.size.height;
                    g_eff_tab_bar_w_cache = eff_tbw;
                    g_resized = 1;
                    g_scroll_offset = 0;
                    g_full_redraw = 1;
                    apply_grid_layout(f);
                    // The hexa VT parser writes to g_term_grid, so we
                    // publish the ACTIVE tab's tile dims as the "window"
                    // size — the parser re-inits and wraps at tile_cols.
                    if (g_active_tab >= 0 && g_active_tab < g_num_tabs) {
                        int ar = g_tabs[g_active_tab].tile_rows;
                        int ac = g_tabs[g_active_tab].tile_cols;
                        if (ar > 0 && ac > 0) {
                            g_term_rows = ar;
                            g_term_cols = ac;
                        }
                    }
                    g_layout_dirty = 0;
                }
            } else {
                // Stacked mode: classic path — all tabs share g_term_rows/cols.
                int new_cols = (int)((f.size.width - eff_tbw) / g_term_cw);
                int new_rows = (int)(f.size.height / g_term_ch);
                if (new_cols < 20) new_cols = 20;
                if (new_rows < 5)  new_rows = 5;
                if (new_cols > TERM_MAX_COLS) new_cols = TERM_MAX_COLS;
                if (new_rows > TERM_MAX_ROWS) new_rows = TERM_MAX_ROWS;
                if (new_cols != g_term_cols || new_rows != g_term_rows ||
                    tbw_changed || g_layout_dirty) {
                    g_term_cols = new_cols;
                    g_term_rows = new_rows;
                    g_eff_tab_bar_w_cache = eff_tbw;
                    g_resized = 1;
                    g_scroll_offset = 0;
                    g_full_redraw = 1;
                    // Mirror shared dims onto each tab's tile_rows/cols so
                    // a later grid toggle starts from a consistent base.
                    struct winsize ws;
                    ws.ws_row = (unsigned short)new_rows;
                    ws.ws_col = (unsigned short)new_cols;
                    ws.ws_xpixel = 0;
                    ws.ws_ypixel = 0;
                    for (int t = 0; t < g_num_tabs; t++) {
                        if (!g_tabs[t].used) continue;
                        g_tabs[t].tile_rows = new_rows;
                        g_tabs[t].tile_cols = new_cols;
                        if (g_tabs[t].pty_fd >= 0)
                            ioctl(g_tabs[t].pty_fd, TIOCSWINSZ, &ws);
                    }
                    g_layout_dirty = 0;
                }
            }
        }
        // Drain background tabs so their shells don't stall, and flag
        // alarm / update Dock badge as Terminal.app does.
        poll_background_tabs();

        // SIGUSR1 → speculative hot swap. Handler only flips the flag;
        // we do the real work here so the main loop (and all g_tabs[]
        // state) is in a quiescent point between ticks.
        if (g_swap_flag) {
            g_swap_flag = 0;
            perform_hot_swap();
            // If perform_hot_swap returned we either aborted (child
            // failed) or are about to _exit; fall through to the next
            // tick so the runloop drains cleanly.
        }
    }
    return g_term_quit;
}

// Returns 1 if window was resized since last check, 0 otherwise.
long hexa_appkit_term_check_resize(void) {
    if (g_resized) { g_resized = 0; return 1; }
    return 0;
}

// ── Background tab activity polling (alarm + dock badge) ──
//
// Why: the hexa main loop only reads the ACTIVE tab's PTY, so background
// tabs' shells will stall once the kernel PTY buffer fills (~16 KB).
// This polls all non-active tabs each loop tick, drains their PTY into
// a discard buffer (so the shell doesn't block), and flags `has_alarm`
// so the tab bar and Dock icon can show a pending indicator like
// Terminal.app's bell/badge.
//
// Trade-off: background tab output is currently discarded. Switching to
// a background tab shows the prompt but not the history between switches.
// A follow-up milestone will store background bytes in a per-tab raw
// ring buffer and replay them through the VT parser on activation.

static int g_last_badge = -1;

static void update_dock_badge(void) {
    int count = 0;
    for (int i = 0; i < g_num_tabs; i++)
        if (g_tabs[i].used && g_tabs[i].has_alarm) count++;
    if (count == g_last_badge) return;
    g_last_badge = count;
    @autoreleasepool {
        NSDockTile *dock = [NSApp dockTile];
        if (count > 0)
            [dock setBadgeLabel:[NSString stringWithFormat:@"%d", count]];
        else
            [dock setBadgeLabel:nil];
    }
}

// bg_tab_write_bytes: best-effort plain-text writer for background tabs in
// grid mode. Bytes are written cell-by-cell into the tab's own grid
// (NOT g_term_grid). ANSI escape sequences are stripped (ESC [ ... final,
// ESC ] ... BEL, two-byte ESC X). Printable ASCII advances the column,
// wrapping at tile_cols. LF scrolls within the tile. CR resets col. BS
// steps back one. TAB rounds up to the next 8-col stop. Wide chars and
// SGR colours are dropped — this is a minimal "show something" mode so
// the user can see activity rather than a frozen snapshot. The active
// tab's grid is still produced by the full hexa VT parser.
static void bg_tab_write_bytes(VoidTab *tab, const char *buf, int n) {
    if (!tab) return;
    int rows = tab->tile_rows > 0 ? tab->tile_rows : g_term_rows;
    int cols = tab->tile_cols > 0 ? tab->tile_cols : g_term_cols;
    if (rows > TERM_MAX_ROWS) rows = TERM_MAX_ROWS;
    if (cols > TERM_MAX_COLS) cols = TERM_MAX_COLS;
    if (rows <= 0 || cols <= 0) return;
    int r = tab->bg_cur_row;
    int c = tab->bg_cur_col;
    if (r < 0) r = 0; if (r >= rows) r = rows - 1;
    if (c < 0) c = 0; if (c >= cols) c = cols - 1;
    for (int i = 0; i < n; i++) {
        unsigned char b = (unsigned char)buf[i];
        // ESC state machine — consumes the rest of a CSI / OSC / SS3 etc.
        if (tab->bg_esc_state == 1) {
            if (b == '[' || b == ']') {
                tab->bg_esc_state = 2;
            } else {
                // Two-byte sequences like ESC =, ESC >, ESC c, etc. — drop.
                tab->bg_esc_state = 0;
            }
            continue;
        }
        if (tab->bg_esc_state == 2) {
            // CSI final byte is 0x40..0x7E. OSC terminates on BEL (0x07)
            // or ST (ESC \) — we treat BEL as universal terminator to keep
            // the loop bounded. Intermediate/parameter bytes are just swallowed.
            if (b == 0x07) {
                tab->bg_esc_state = 0;
            } else if (b >= 0x40 && b <= 0x7E) {
                tab->bg_esc_state = 0;
            }
            continue;
        }
        // ESC introducer
        if (b == 0x1B) { tab->bg_esc_state = 1; continue; }
        // Controls
        if (b == '\r') { c = 0; continue; }
        if (b == '\n') {
            c = 0;
            r++;
            if (r >= rows) {
                // Scroll the tile grid up by one row so the prompt stays visible.
                for (int rr = 0; rr < rows - 1; rr++) {
                    memcpy(tab->grid[rr], tab->grid[rr + 1],
                           sizeof(TermCell) * cols);
                }
                // Clear the newly vacated bottom row.
                for (int cc = 0; cc < cols; cc++) {
                    tab->grid[rows - 1][cc].ch = ' ';
                    tab->grid[rows - 1][cc].fg = 7;
                    tab->grid[rows - 1][cc].bg = 0;
                    tab->grid[rows - 1][cc].flags = 0;
                }
                r = rows - 1;
            }
            continue;
        }
        if (b == 0x08) { if (c > 0) c--; continue; }
        if (b == '\t') {
            c = (c + 8) & ~7;
            if (c >= cols) c = cols - 1;
            continue;
        }
        if (b < 0x20) continue;     // other C0 controls
        if (b >= 0x80) continue;    // multi-byte UTF-8 — drop leading/cont
        if (c >= cols) {
            c = 0; r++;
            if (r >= rows) {
                for (int rr = 0; rr < rows - 1; rr++)
                    memcpy(tab->grid[rr], tab->grid[rr + 1],
                           sizeof(TermCell) * cols);
                for (int cc = 0; cc < cols; cc++) {
                    tab->grid[rows - 1][cc].ch = ' ';
                    tab->grid[rows - 1][cc].fg = 7;
                    tab->grid[rows - 1][cc].bg = 0;
                    tab->grid[rows - 1][cc].flags = 0;
                }
                r = rows - 1;
            }
        }
        tab->grid[r][c].ch = (unichar)b;
        tab->grid[r][c].fg = 7;
        tab->grid[r][c].bg = 0;
        tab->grid[r][c].flags = 0;
        c++;
    }
    if (c >= cols) c = cols - 1;
    if (r >= rows) r = rows - 1;
    tab->bg_cur_row = r;
    tab->bg_cur_col = c;
}

static void poll_background_tabs(void) {
    if (g_num_tabs < 2) return;
    char buf[4096];
    int changed = 0;
    int grid_mode = (g_layout_mode == LAYOUT_GRID && g_num_tabs <= 9);
    for (int i = 0; i < g_num_tabs; i++) {
        if (i == g_active_tab) continue;
        VoidTab *tab = &g_tabs[i];
        if (!tab->used || tab->pty_fd < 0) continue;
        // Drain non-blocking (fd is already O_NONBLOCK from spawn).
        ssize_t total = 0;
        while (1) {
            ssize_t n = read(tab->pty_fd, buf, sizeof(buf));
            if (n <= 0) break;
            total += n;
            if (grid_mode) bg_tab_write_bytes(tab, buf, (int)n);
            if (total > 65536) break; // stay bounded per tick
        }
        if (total > 0 && !tab->has_alarm) {
            tab->has_alarm = 1;
            changed = 1;
        }
        if (total > 0 && grid_mode) {
            // Repaint just this tile so the new content shows up immediately.
            if (g_window) {
                NSRect bnds = [[g_window contentView] bounds];
                NSRect tile = compute_tile_rect(i, bnds, g_num_tabs);
                [[g_window contentView] setNeedsDisplayInRect:tile];
            }
        }
    }
    if (changed) {
        update_dock_badge();
        int eff_tbw = effective_tab_bar_w();
        if (g_window && eff_tbw > 0)
            [[g_window contentView] setNeedsDisplayInRect:
                NSMakeRect(0, 0, eff_tbw, [[g_window contentView] bounds].size.height)];
    }
}

// Clear alarm on the now-active tab. Called from every tab-switch path.
static void clear_active_alarm(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return;
    if (g_tabs[g_active_tab].has_alarm) {
        g_tabs[g_active_tab].has_alarm = 0;
        update_dock_badge();
    }
}

// Get current terminal dimensions
long hexa_appkit_term_get_rows(void) { return (long)g_term_rows; }
long hexa_appkit_term_get_cols(void) { return (long)g_term_cols; }

// Forward keys from AppKit to the active tab's PTY. All in C.
long hexa_keys_to_pty(long master_fd) {
    char buf[4096];
    int avail = g_term_kw - g_term_kr;
    if (avail <= 0) return 0;
    if (avail > 4096) avail = 4096;
    for (int i = 0; i < avail; i++) {
        buf[i] = g_term_keys[g_term_kr % TERM_KEY_SIZE];
        g_term_kr++;
    }
    // Clear is_blank ONLY on Enter (command execution), not on every
    // keystroke. Typing `ssh foo` without hitting Enter keeps the tab
    // convertible; hitting Enter runs something so the tab is no longer
    // pristine and a profile shortcut must open a new tab instead.
    if (g_active_tab >= 0 && g_active_tab < g_num_tabs &&
        g_tabs[g_active_tab].is_blank) {
        for (int i = 0; i < avail; i++) {
            if (buf[i] == '\r' || buf[i] == '\n') {
                g_tabs[g_active_tab].is_blank = 0;
                break;
            }
        }
    }
    return (long)write((int)master_fd, buf, avail);
}

// OSC title buffer
static char g_term_title_buf[256];
static int g_term_title_len = 0;

void hexa_appkit_term_title_reset(void) {
    g_term_title_len = 0;
    g_term_title_buf[0] = '\0';
}

void hexa_appkit_term_title_push(long b) {
    if (g_term_title_len < 255) {
        g_term_title_buf[g_term_title_len++] = (char)b;
        g_term_title_buf[g_term_title_len] = '\0';
    }
}

void hexa_appkit_term_title_apply(void) {
    // Profile-opened tabs lock their title — shell OSC 0 escapes (which
    // nearly every prompt emits) must not clobber "nexus (1)".
    if (g_active_tab >= 0 && g_active_tab < g_num_tabs) {
        if (g_tabs[g_active_tab].title_locked) {
            // Still reflect the locked name in the window title so the
            // user sees which project is active, but ignore the OSC 0
            // payload entirely.
            if (g_window) {
                @autoreleasepool {
                    NSString *t = [NSString stringWithFormat:@"VOID — %s",
                                   g_tabs[g_active_tab].title];
                    [g_window setTitle:t];
                }
            }
            return;
        }
        strncpy(g_tabs[g_active_tab].title, g_term_title_buf,
                sizeof(g_tabs[g_active_tab].title) - 1);
    }
    if (!g_window) return;
    @autoreleasepool {
        NSString *t = [NSString stringWithFormat:@"VOID — %s", g_term_title_buf];
        [g_window setTitle:t];
    }
}

// ── OSC 7 CWD handlers ──
// Shell emits `ESC ] 7 ; file://host/path ST` on prompt. hexa VT parser
// strips the OSC 7 payload and feeds it byte-by-byte through these
// functions. We parse the URL into a plain filesystem path stored on
// the active VoidTab, which is then the anchor for future file-completion.
static char g_cwd_buf[1024];
static int g_cwd_len = 0;

void hexa_appkit_cwd_reset(void) {
    g_cwd_len = 0;
    g_cwd_buf[0] = '\0';
}

void hexa_appkit_cwd_push(long b) {
    if (g_cwd_len < (int)sizeof(g_cwd_buf) - 1) {
        g_cwd_buf[g_cwd_len++] = (char)b;
        g_cwd_buf[g_cwd_len] = '\0';
    }
}

// Decode a single percent-escape (%XX) hex pair. Returns the byte value
// and advances `*i` past the escape if valid, else returns -1 and leaves
// `*i` unchanged.
static int url_unhex(const char *s, int *i, int len) {
    if (*i + 2 >= len) return -1;
    char h = s[*i + 1], l = s[*i + 2];
    int hv, lv;
    if      (h >= '0' && h <= '9') hv = h - '0';
    else if (h >= 'a' && h <= 'f') hv = 10 + (h - 'a');
    else if (h >= 'A' && h <= 'F') hv = 10 + (h - 'A');
    else return -1;
    if      (l >= '0' && l <= '9') lv = l - '0';
    else if (l >= 'a' && l <= 'f') lv = 10 + (l - 'a');
    else if (l >= 'A' && l <= 'F') lv = 10 + (l - 'A');
    else return -1;
    *i += 3;
    return (hv << 4) | lv;
}

void hexa_appkit_cwd_apply(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return;
    // OSC 7 payload format: "file://<host>/<path>"
    // Skip the scheme and host to get the path.
    const char *p = g_cwd_buf;
    if (g_cwd_len >= 7 && strncmp(p, "file://", 7) == 0) {
        p += 7;
        // Skip host (up to next '/')
        while (*p && *p != '/') p++;
    }
    if (!*p) return;

    // URL-decode the path into the tab's cwd field.
    VoidTab *tab = &g_tabs[g_active_tab];
    char *out = tab->cwd;
    size_t cap = sizeof(tab->cwd) - 1;
    size_t o = 0;
    int plen = (int)strlen(p);
    int i = 0;
    while (i < plen && o < cap) {
        if (p[i] == '%') {
            int dec = url_unhex(p, &i, plen);
            if (dec < 0) { out[o++] = p[i++]; }
            else         { out[o++] = (char)dec; }
        } else {
            out[o++] = p[i++];
        }
    }
    out[o] = '\0';
}

// Accessor used by future autocomplete code (C-internal).
// Returns NULL if no active tab or cwd unknown.
const char *hexa_tab_cwd(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return NULL;
    const char *c = g_tabs[g_active_tab].cwd;
    return c[0] ? c : NULL;
}

// ── Section-based scrollback ──
//
// Data model:
//   A VoidTab owns a ring of SB_MAX_SECTIONS SbSection slots. Each section
//   holds SB_SECTION_LINES rows × TERM_MAX_COLS cells, lazy-allocated on
//   first write (~410 KB/section). Sections are appended at the "tail"
//   (head + num - 1); when the ring fills and a new line arrives, the
//   oldest section is freed and the head advances.
//
// Benefit vs. the old flat 1000-line ring:
//   - Idle tab: 0 bytes (was 0 bytes — same)
//   - 100 lines of scrollback: 2 sections = ~820 KB (was 6.4 MB)
//   - 2048 lines (full): 32 sections = ~13 MB (was 6.4 MB, fewer lines)
//   - Load on ring overflow: free() one section instead of overwrite
//     of 1000 lines' worth of slots — steady-state memory bounded and
//     reclaimable.

static TermCell *sb_cur_row_ptr = NULL; // cell[] pointer for active push row

long hexa_scrollback_push_begin(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return -1;
    VoidTab *tab = &g_tabs[g_active_tab];

    // Determine which section gets the new line.
    int tail;
    if (tab->sb_num == 0) {
        // First ever line for this tab
        tab->sb_head = 0;
        tab->sb_num = 1;
        tail = 0;
    } else {
        tail = (tab->sb_head + tab->sb_num - 1) % SB_MAX_SECTIONS;
        if (tab->sb[tail].lines >= SB_SECTION_LINES) {
            // Current tail is full — advance.
            if (tab->sb_num == SB_MAX_SECTIONS) {
                // Ring full: free the oldest section before reusing slot.
                int old = tab->sb_head;
                if (tab->sb[old].cells) {
                    free(tab->sb[old].cells);
                    tab->sb[old].cells = NULL;
                }
                tab->sb_total -= tab->sb[old].lines;
                tab->sb[old].lines = 0;
                tab->sb_head = (tab->sb_head + 1) % SB_MAX_SECTIONS;
                tab->sb_num--;
            }
            tail = (tab->sb_head + tab->sb_num) % SB_MAX_SECTIONS;
            tab->sb_num++;
        }
    }

    // Lazy alloc the target section.
    if (!tab->sb[tail].cells) {
        tab->sb[tail].cells = calloc(
            (size_t)SB_SECTION_LINES * TERM_MAX_COLS, sizeof(TermCell));
        if (!tab->sb[tail].cells) {
            // Allocation failed; roll back the advance.
            if (tab->sb_num > 1) tab->sb_num--;
            return -1;
        }
        tab->sb[tail].lines = 0;
    }

    sb_cur_row_ptr = &tab->sb[tail].cells[tab->sb[tail].lines * TERM_MAX_COLS];
    g_sb_push_col = 0;
    return 0;
}

long hexa_scrollback_push_cell(long ch, long fg, long bg, long flags) {
    if (!sb_cur_row_ptr || g_sb_push_col >= TERM_MAX_COLS) return -1;
    TermCell *dst = &sb_cur_row_ptr[g_sb_push_col];
    dst->ch = (unichar)ch;
    dst->fg = (int)fg;
    dst->bg = (int)bg;
    dst->flags = (int)flags;
    g_sb_push_col++;
    return 0;
}

long hexa_scrollback_push_end(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs || !sb_cur_row_ptr) return -1;
    VoidTab *tab = &g_tabs[g_active_tab];
    // Pad remaining columns with spaces
    while (g_sb_push_col < TERM_MAX_COLS) {
        TermCell *dst = &sb_cur_row_ptr[g_sb_push_col];
        dst->ch = ' ';
        dst->fg = 7;
        dst->bg = 0;
        dst->flags = 0;
        g_sb_push_col++;
    }
    int tail = (tab->sb_head + tab->sb_num - 1) % SB_MAX_SECTIONS;
    tab->sb[tail].lines++;
    tab->sb_total++;
    sb_cur_row_ptr = NULL;
    return 0;
}

long hexa_scrollback_count(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return 0;
    return (long)g_tabs[g_active_tab].sb_total;
}

// Fetch a scrollback line by logical index (0 = oldest live line).
// Returns NULL if out of range.
static TermCell *sb_line_ptr(struct VoidTab_ *tab, int logical_line) {
    if (logical_line < 0 || logical_line >= tab->sb_total) return NULL;
    // Walk sections from head until we've skipped `logical_line` lines.
    int remain = logical_line;
    for (int i = 0; i < tab->sb_num; i++) {
        int idx = (tab->sb_head + i) % SB_MAX_SECTIONS;
        SbSection *sec = &tab->sb[idx];
        if (remain < sec->lines)
            return &sec->cells[remain * TERM_MAX_COLS];
        remain -= sec->lines;
    }
    return NULL;
}

// Memory usage report (in bytes) for the active tab's scrollback — used
// by the section-eviction test and for debugging.
long hexa_scrollback_mem_bytes(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return 0;
    VoidTab *tab = &g_tabs[g_active_tab];
    long n = 0;
    for (int s = 0; s < SB_MAX_SECTIONS; s++) {
        if (tab->sb[s].cells) n += (long)SB_SECTION_LINES * TERM_MAX_COLS * sizeof(TermCell);
    }
    return n;
}
