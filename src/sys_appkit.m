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
} VoidTab;

static VoidTab g_tabs[MAX_TABS];
static int g_num_tabs = 0;
static int g_active_tab = -1;
static int g_tab_cmd = 0; // 0=none, 1=new, 2=close

// Effective tab bar width — 0 when there is only one tab (matches
// Safari/Terminal.app: the chrome disappears so the user reclaims the pixels).
// Becomes TAB_BAR_W the moment a second tab is created, and collapses back
// when closed. A static cache of the last value drives the reflow check in
// the main event loop so window columns recompute exactly once per transition.
static int g_eff_tab_bar_w_cache = -1;
static inline int effective_tab_bar_w(void) {
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
static NSColor *g_term_color_cache[16] = {0}; // retained ANSI palette
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
            int bg = cell->bg, fg = cell->fg;
            if (cell->flags & 8) { int t = bg; bg = fg; fg = t; }
            if (bg != 0) {
                [term_color(bg) setFill];
                NSRectFill(NSMakeRect(x, y, g_term_cw, g_term_ch));
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
    } // @autoreleasepool
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
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
                [self setNeedsDisplay:YES];
            }
        }
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (g_drag_source < 0) return;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
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
}

- (void)mouseUp:(NSEvent *)event {
    if (g_drag_active && g_drag_source != g_drag_target &&
        g_drag_source >= 0 && g_drag_target >= 0) {
        tabs_move(g_drag_source, g_drag_target);
        [self setNeedsDisplay:YES];
    }
    g_drag_source = -1;
    g_drag_target = -1;
    g_drag_active = 0;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags mods = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (!(mods & NSEventModifierFlagCommand)) return [super performKeyEquivalent:event];

    NSString *raw = [event charactersIgnoringModifiers];
    if (!raw.length) return [super performKeyEquivalent:event];
    unichar ch = [raw characterAtIndex:0];

    if (ch == 't') { g_tab_cmd = 1; return YES; } // Cmd+T new tab
    if (ch == 'w') { g_tab_cmd = 2; return YES; } // Cmd+W close tab
    if (ch == 'q') { g_term_quit = 1; return YES; } // Cmd+Q quit
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
@interface HexaTermDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end
@implementation HexaTermDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }
- (void)applicationWillTerminate:(NSNotification *)n { g_term_quit = 1; }
- (void)windowWillClose:(NSNotification *)n { g_term_quit = 1; }
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
typedef struct {
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
                "    { \"key\": \"3\", \"title\": \"airgenome\",     \"path\": \"~/Dev/airgenome\",        \"cmd\": \"cl\" },\n"
                "    { \"key\": \"4\", \"title\": \"n6-arch\",       \"path\": \"~/Dev/n6-architecture\",  \"cmd\": \"cl\" },\n"
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
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        g_term_delegate = [[HexaTermDelegate alloc] init];
        [app setDelegate:g_term_delegate];

        // Match Terminal.app: SFMono-Regular 13pt (fallback chain)
        long fs = font_size > 0 ? font_size : 13;
        g_term_font = CTFontCreateWithName(CFSTR("SFMono-Regular"), fs, NULL);
        if (!g_term_font) g_term_font = CTFontCreateWithName(CFSTR("Menlo-Regular"), fs, NULL);
        if (!g_term_font) g_term_font = CTFontCreateWithName(CFSTR("Monaco"), fs, NULL);

        // Cache bold variant ONCE at startup. Creating it per-cell-per-frame
        // (CTFontCreateCopyWithSymbolicTraits) thrashes CGFont cache and
        // crashed Terminal.app via CGFontStrikeRelease → free_tiny.
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

        // Menu bar
        NSMenu *mb = [[NSMenu alloc] init];
        NSMenuItem *mi = [[NSMenuItem alloc] init];
        [mb addItem:mi];
        [app setMainMenu:mb];
        NSMenu *am = [[NSMenu alloc] init];
        [am addItemWithTitle:@"Quit VOID" action:@selector(terminate:) keyEquivalent:@"q"];
        [mi setSubmenu:am];

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

// Convert a blank tab to a live profile (or plain shell) tab in place.
// Kills the existing (still-pristine) shell PTY first, then spawns the
// profile PTY in its place. Locks the title, clears is_blank, resets
// hexa's VT state via g_resized, triggers a full redraw. Used by
// Cmd+Ctrl+N / Cmd+T when the active tab is blank.
static int tab_become_profile(int idx, VoidProfile *vp) {
    if (idx < 0 || idx >= g_num_tabs) return -1;
    if (!g_tabs[idx].used) return -1;
    if (!g_tabs[idx].is_blank) return -1; // never clobber a live tab

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
    int fd = tab_spawn_pty_profile(vp);
    if (fd < 0) return -1;

    g_tabs[idx].used = 1;
    g_tabs[idx].pty_fd = fd;
    g_tabs[idx].pid = 0;
    g_tabs[idx].is_blank = make_blank ? 1 : 0;

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

    // Renumber profile group now that the new sibling is in place.
    void_tabs_renumber_profiles();

    // Clear active rendering grid for new tab
    tab_clear_grid(g_term_grid);
    g_term_cur_row = 0;
    g_term_cur_col = 0;
    g_full_redraw = 1;

    return (long)idx;
}

// Global used to hand a profile from the Cmd+Ctrl+N intercept to
// hexa_tab_new (called on the hexa main-loop tick). Only valid
// for the single new-tab request immediately following the keypress.
VoidProfile *g_pending_profile = NULL;

// Close a tab. Kills PTY. Returns new active tab index (or -1 if last tab closed).
long hexa_tab_close(long idx) {
    if (idx < 0 || idx >= g_num_tabs) return g_active_tab;
    if (!g_tabs[idx].used) return g_active_tab;

    // Kill PTY
    if (g_tabs[idx].pty_fd >= 0) {
        close(g_tabs[idx].pty_fd);
        g_tabs[idx].pty_fd = -1;
    }
    if (g_tabs[idx].pid > 0) {
        kill(g_tabs[idx].pid, SIGTERM);
        waitpid(g_tabs[idx].pid, NULL, WNOHANG);
    }
    g_tabs[idx].used = 0;

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

void hexa_appkit_term_set_cell(long row, long col, long ch, long fg, long bg, long flags) {
    if (row < 0 || row >= TERM_MAX_ROWS || col < 0 || col >= TERM_MAX_COLS) return;
    TermCell *cp = &g_term_grid[row][col];
    // Equal-cell early exit: hexa's sync_to_bridge writes the whole grid every
    // frame; this cuts ~90% of writes for typing workloads.
    if (cp->ch == (unichar)ch && cp->fg == (int)fg &&
        cp->bg == (int)bg && cp->flags == (int)flags) return;
    cp->ch = (unichar)ch;
    cp->fg = (int)fg;
    cp->bg = (int)bg;
    cp->flags = (int)flags;
    // Mark dirty range
    if (g_dirty_min < 0 || (int)row < g_dirty_min) g_dirty_min = (int)row;
    if ((int)row > g_dirty_max) g_dirty_max = (int)row;
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

void hexa_appkit_term_flush(void) {
    @autoreleasepool {
        NSView *v = [g_window contentView];
        if (!v) return;
        if (g_full_redraw || g_scroll_offset > 0) {
            // Tab switch, resize, or scrollback view — redraw everything.
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
                        // Special case: if the active tab is blank (no
                        // PTY — happens at app launch), convert it in
                        // place instead of opening a second tab.
                        if (with_ctrl && ch >= '0' && ch <= '9') {
                            VoidProfile *vp = profile_by_key((char)ch);
                            if (vp) {
                                if (g_active_tab >= 0 &&
                                    g_active_tab < g_num_tabs &&
                                    g_tabs[g_active_tab].is_blank &&
                                    tab_become_profile(g_active_tab, vp) == 0) {
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

                        if (ch >= 'A' && ch <= 'Z') ch += 32; // tolower
                        if (ch == 't') {
                            // Blank active tab → convert to a plain shell
                            // in place; otherwise hand off to hexa for a
                            // fresh new tab.
                            if (g_active_tab >= 0 &&
                                g_active_tab < g_num_tabs &&
                                g_tabs[g_active_tab].is_blank &&
                                tab_become_profile(g_active_tab, NULL) == 0) {
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
            int new_cols = (int)((f.size.width - eff_tbw) / g_term_cw);
            int new_rows = (int)(f.size.height / g_term_ch);
            if (new_cols < 20) new_cols = 20;
            if (new_rows < 5) new_rows = 5;
            if (new_cols > TERM_MAX_COLS) new_cols = TERM_MAX_COLS;
            if (new_rows > TERM_MAX_ROWS) new_rows = TERM_MAX_ROWS;
            int tbw_changed = (eff_tbw != g_eff_tab_bar_w_cache);
            if (new_cols != g_term_cols || new_rows != g_term_rows || tbw_changed) {
                g_term_cols = new_cols;
                g_term_rows = new_rows;
                g_eff_tab_bar_w_cache = eff_tbw;
                g_resized = 1;
                g_scroll_offset = 0;
                g_full_redraw = 1;
                // Notify ALL tabs' PTYs of new size
                struct winsize ws;
                ws.ws_row = (unsigned short)new_rows;
                ws.ws_col = (unsigned short)new_cols;
                ws.ws_xpixel = 0;
                ws.ws_ypixel = 0;
                for (int t = 0; t < g_num_tabs; t++) {
                    if (g_tabs[t].used && g_tabs[t].pty_fd >= 0)
                        ioctl(g_tabs[t].pty_fd, TIOCSWINSZ, &ws);
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

static void poll_background_tabs(void) {
    if (g_num_tabs < 2) return;
    char discard[4096];
    int changed = 0;
    for (int i = 0; i < g_num_tabs; i++) {
        if (i == g_active_tab) continue;
        VoidTab *tab = &g_tabs[i];
        if (!tab->used || tab->pty_fd < 0) continue;
        // Drain non-blocking (fd is already O_NONBLOCK from spawn).
        ssize_t total = 0;
        while (1) {
            ssize_t n = read(tab->pty_fd, discard, sizeof(discard));
            if (n <= 0) break;
            total += n;
            if (total > 65536) break; // stay bounded per tick
        }
        if (total > 0 && !tab->has_alarm) {
            tab->has_alarm = 1;
            changed = 1;
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
