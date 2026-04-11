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
#define SCROLLBACK_LINES 1000
#define TAB_BAR_W 140
#define TAB_ROW_H 28

typedef struct {
    unichar ch;
    int fg, bg, flags;
} TermCell;

// ── Tab state ──
typedef struct {
    int used;
    int pty_fd;
    pid_t pid;
    TermCell grid[TERM_MAX_ROWS][TERM_MAX_COLS];
    int cur_row, cur_col;
    char title[128];
    // Scrollback ring buffer (heap-allocated on first push)
    TermCell *scrollback;   // SCROLLBACK_LINES * TERM_MAX_COLS cells
    int sb_head;            // next write position in ring
    int sb_count;           // lines stored (max SCROLLBACK_LINES)
} VoidTab;

static VoidTab g_tabs[MAX_TABS];
static int g_num_tabs = 0;
static int g_active_tab = -1;
static int g_tab_cmd = 0; // 0=none, 1=new, 2=close

// Active tab's rendering grid (synced from hexa)
static TermCell g_term_grid[TERM_MAX_ROWS][TERM_MAX_COLS];
static int g_term_rows = 24;
static int g_term_cols = 80;
static int g_term_cur_row = 0;
static int g_term_cur_col = 0;
static int g_term_cur_vis = 1;
static float g_term_cw = 0;
static float g_term_ch = 0;
static CTFontRef g_term_font = NULL;
static CTFontRef g_term_font_bold = NULL;
static NSColor *g_term_color_cache[16] = {0}; // retained ANSI palette
static int g_term_quit = 0;
static int g_scroll_offset = 0;    // 0 = live view, >0 = lines scrolled back
static int g_sb_push_col = 0;      // temp column index during row push

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

    // ── Tab bar (left panel) ──
    [[NSColor colorWithRed:0.11 green:0.11 blue:0.11 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0, 0, TAB_BAR_W, bounds.size.height));

    // Separator line
    [[NSColor colorWithRed:0.20 green:0.20 blue:0.20 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(TAB_BAR_W - 1, 0, 1, bounds.size.height));

    NSFont *tabFont = [NSFont systemFontOfSize:11];
    for (int t = 0; t < g_num_tabs; t++) {
        float ty = 4 + t * TAB_ROW_H;
        // Active tab highlight
        if (t == g_active_tab) {
            [[NSColor colorWithRed:0.18 green:0.18 blue:0.18 alpha:1.0] setFill];
            NSRectFill(NSMakeRect(0, ty, TAB_BAR_W - 1, TAB_ROW_H));
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
    }

    // ── Terminal grid (right of tab bar) ──
    float ox = TAB_BAR_W;
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

        // Determine cell source: scrollback ring or live grid
        TermCell *cell_row = NULL;
        if (g_scroll_offset > 0 && atab) {
            int sb_n = atab->sb_count;
            int vline = sb_n - g_scroll_offset + r;
            if (vline >= 0 && vline < sb_n && atab->scrollback) {
                int ring = (atab->sb_head - sb_n + vline + SCROLLBACK_LINES) % SCROLLBACK_LINES;
                cell_row = &atab->scrollback[ring * TERM_MAX_COLS];
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
                         g_scroll_offset, atab ? atab->sb_count : 0];
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
    if (p.x < TAB_BAR_W) {
        int idx = (int)((p.y - 4) / TAB_ROW_H);
        if (idx >= 0 && idx < g_num_tabs && idx != g_active_tab) {
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
            [self setNeedsDisplay:YES];
        }
    }
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
    // Cmd+1~9: switch to tab N-1
    if (ch >= '1' && ch <= '9') {
        int target = ch - '1';
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
            int max_sb = (tab && tab->scrollback) ? tab->sb_count : 0;
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
    int max_sb = (tab->scrollback) ? tab->sb_count : 0;
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

// ── Tab management (C-internal) ──

static int tab_spawn_pty(void) {
    // Pass actual window size to forkpty so PTY starts correct
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
        char *shell = getenv("SHELL");
        if (!shell) shell = "/bin/sh";
        execl(shell, shell, "-l", (char*)NULL);
        _exit(127);
    }
    // Non-blocking
    int fl = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, fl | O_NONBLOCK);
    return master;
}

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
    if (!try_single_instance()) {
        fprintf(stderr, "[void] already running\n");
        return -1;
    }
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
        // Auto-size from screen (ignore passed rows/cols)
        NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
        float ww = screenFrame.size.width * 0.85;
        float wh = screenFrame.size.height * 0.85;
        g_term_cols = (int)((ww - TAB_BAR_W) / g_term_cw);
        g_term_rows = (int)(wh / g_term_ch);
        if (g_term_cols < 80) g_term_cols = 80;
        if (g_term_rows < 24) g_term_rows = 24;
        if (g_term_cols > TERM_MAX_COLS) g_term_cols = TERM_MAX_COLS;
        if (g_term_rows > TERM_MAX_ROWS) g_term_rows = TERM_MAX_ROWS;

        tab_clear_grid(g_term_grid);

        ww = TAB_BAR_W + g_term_cw * g_term_cols;
        wh = g_term_ch * g_term_rows;
        float wx = screenFrame.origin.x + (screenFrame.size.width - ww) / 2;
        float wy = screenFrame.origin.y + (screenFrame.size.height - wh) / 2;
        NSRect frame = NSMakeRect(wx, wy, ww, wh);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        g_window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                                 backing:NSBackingStoreBuffered defer:NO];
        [g_window setTitle:@"VOID"];
        [g_window setDelegate:g_term_delegate];
        [g_window setMinSize:NSMakeSize(TAB_BAR_W + g_term_cw * 20, g_term_ch * 5)];
        if (@available(macOS 10.14, *))
            [g_window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [g_window setBackgroundColor:[NSColor blackColor]];

        NSView *tv = [[HexaTermView alloc] initWithFrame:frame];
        [g_window setContentView:tv];
        [g_window makeFirstResponder:tv];
        [g_window makeKeyAndOrderFront:nil];

        // Menu bar
        NSMenu *mb = [[NSMenu alloc] init];
        NSMenuItem *mi = [[NSMenuItem alloc] init];
        [mb addItem:mi];
        [app setMainMenu:mb];
        NSMenu *am = [[NSMenu alloc] init];
        [am addItemWithTitle:@"Quit VOID" action:@selector(terminate:) keyEquivalent:@"q"];
        [mi setSubmenu:am];

        // App icon — programmatic "V"
        NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(128, 128)];
        [icon lockFocus];
        [[NSColor colorWithRed:0.10 green:0.10 blue:0.18 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, 128, 128));
        NSDictionary *iconAttrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:72],
            NSForegroundColorAttributeName: [NSColor colorWithRed:0.5 green:0.5 blue:1.0 alpha:1.0]
        };
        [@"V" drawAtPoint:NSMakePoint(28, 20) withAttributes:iconAttrs];
        [icon unlockFocus];
        [app setApplicationIconImage:icon];

        [app finishLaunching];
        [app activateIgnoringOtherApps:YES];
    }
    return 0;
}

// ── Tab API for hexa ──

// Create a new tab. Spawns PTY, returns tab index (or -1).
long hexa_tab_new(void) {
    if (g_num_tabs >= MAX_TABS) return -1;

    // Save current active tab's grid
    if (g_active_tab >= 0 && g_active_tab < g_num_tabs) {
        memcpy(g_tabs[g_active_tab].grid, g_term_grid, sizeof(g_term_grid));
        g_tabs[g_active_tab].cur_row = g_term_cur_row;
        g_tabs[g_active_tab].cur_col = g_term_cur_col;
    }

    int idx = g_num_tabs;
    int fd = tab_spawn_pty();
    if (fd < 0) return -1;

    g_tabs[idx].used = 1;
    g_tabs[idx].pty_fd = fd;
    g_tabs[idx].pid = 0;

    // Set PTY to actual window size immediately
    struct winsize ws;
    ws.ws_row = (unsigned short)g_term_rows;
    ws.ws_col = (unsigned short)g_term_cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    ioctl(fd, TIOCSWINSZ, &ws);
    snprintf(g_tabs[idx].title, sizeof(g_tabs[idx].title), "");
    tab_clear_grid(g_tabs[idx].grid);
    g_tabs[idx].cur_row = 0;
    g_tabs[idx].cur_col = 0;
    g_tabs[idx].scrollback = NULL;
    g_tabs[idx].sb_head = 0;
    g_tabs[idx].sb_count = 0;

    g_num_tabs++;
    g_active_tab = idx;

    // Clear active rendering grid for new tab
    tab_clear_grid(g_term_grid);
    g_term_cur_row = 0;
    g_term_cur_col = 0;

    return (long)idx;
}

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

    // Free scrollback before shift
    if (g_tabs[idx].scrollback) {
        free(g_tabs[idx].scrollback);
        g_tabs[idx].scrollback = NULL;
    }

    // Shift tabs down
    for (int i = (int)idx; i < g_num_tabs - 1; i++) {
        g_tabs[i] = g_tabs[i + 1];
    }
    g_num_tabs--;
    // NULL dead slot to prevent double-free (shift copies pointer)
    if (g_num_tabs < MAX_TABS) {
        g_tabs[g_num_tabs].scrollback = NULL;
        g_tabs[g_num_tabs].sb_head = 0;
        g_tabs[g_num_tabs].sb_count = 0;
    }
    g_scroll_offset = 0;

    if (g_num_tabs == 0) {
        g_active_tab = -1;
        return -1;
    }

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
    g_term_grid[row][col].ch = (unichar)ch;
    g_term_grid[row][col].fg = (int)fg;
    g_term_grid[row][col].bg = (int)bg;
    g_term_grid[row][col].flags = (int)flags;
}

void hexa_appkit_term_set_cursor(long row, long col, long vis) {
    g_term_cur_row = (int)row;
    g_term_cur_col = (int)col;
    g_term_cur_vis = (int)vis;
}

void hexa_appkit_term_flush(void) {
    @autoreleasepool {
        [[g_window contentView] setNeedsDisplay:YES];
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
            // menu/system from stealing Cmd+T/W/Q/1~9.
            if ([ev type] == NSEventTypeKeyDown) {
                NSEventModifierFlags mods = [ev modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
                if (mods & NSEventModifierFlagCommand) {
                    NSString *raw = [ev charactersIgnoringModifiers];
                    if (raw.length > 0) {
                        unichar ch = [raw characterAtIndex:0];
                        if (ch >= 'A' && ch <= 'Z') ch += 32; // tolower
                        if (ch == 't') { g_tab_cmd = 1; continue; }
                        if (ch == 'w') { g_tab_cmd = 2; continue; }
                        if (ch == 'q') { g_term_quit = 1; continue; }
                        if (ch >= '1' && ch <= '9') {
                            int target = ch - '1';
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
        // Check for window resize
        if (g_window && g_term_cw > 0 && g_term_ch > 0) {
            NSRect f = [[g_window contentView] frame];
            int new_cols = (int)((f.size.width - TAB_BAR_W) / g_term_cw);
            int new_rows = (int)(f.size.height / g_term_ch);
            if (new_cols < 20) new_cols = 20;
            if (new_rows < 5) new_rows = 5;
            if (new_cols > TERM_MAX_COLS) new_cols = TERM_MAX_COLS;
            if (new_rows > TERM_MAX_ROWS) new_rows = TERM_MAX_ROWS;
            if (new_cols != g_term_cols || new_rows != g_term_rows) {
                g_term_cols = new_cols;
                g_term_rows = new_rows;
                g_resized = 1;
                g_scroll_offset = 0;
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
    }
    return g_term_quit;
}

// Returns 1 if window was resized since last check, 0 otherwise.
long hexa_appkit_term_check_resize(void) {
    if (g_resized) { g_resized = 0; return 1; }
    return 0;
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
    // Set both window title and active tab title
    if (g_active_tab >= 0 && g_active_tab < g_num_tabs) {
        strncpy(g_tabs[g_active_tab].title, g_term_title_buf,
                sizeof(g_tabs[g_active_tab].title) - 1);
    }
    if (!g_window) return;
    @autoreleasepool {
        NSString *t = [NSString stringWithFormat:@"VOID — %s", g_term_title_buf];
        [g_window setTitle:t];
    }
}

// ── Scrollback ring buffer ──

long hexa_scrollback_push_begin(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return -1;
    VoidTab *tab = &g_tabs[g_active_tab];
    if (!tab->scrollback) {
        tab->scrollback = calloc((size_t)SCROLLBACK_LINES * TERM_MAX_COLS, sizeof(TermCell));
        if (!tab->scrollback) return -1;
    }
    g_sb_push_col = 0;
    return 0;
}

long hexa_scrollback_push_cell(long ch, long fg, long bg, long flags) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return -1;
    VoidTab *tab = &g_tabs[g_active_tab];
    if (!tab->scrollback || g_sb_push_col >= TERM_MAX_COLS) return -1;
    int off = tab->sb_head * TERM_MAX_COLS + g_sb_push_col;
    tab->scrollback[off].ch = (unichar)ch;
    tab->scrollback[off].fg = (int)fg;
    tab->scrollback[off].bg = (int)bg;
    tab->scrollback[off].flags = (int)flags;
    g_sb_push_col++;
    return 0;
}

long hexa_scrollback_push_end(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return -1;
    VoidTab *tab = &g_tabs[g_active_tab];
    if (!tab->scrollback) return -1;
    // Pad remaining columns with spaces
    while (g_sb_push_col < TERM_MAX_COLS) {
        int off = tab->sb_head * TERM_MAX_COLS + g_sb_push_col;
        tab->scrollback[off].ch = ' ';
        tab->scrollback[off].fg = 7;
        tab->scrollback[off].bg = 0;
        tab->scrollback[off].flags = 0;
        g_sb_push_col++;
    }
    tab->sb_head = (tab->sb_head + 1) % SCROLLBACK_LINES;
    if (tab->sb_count < SCROLLBACK_LINES) tab->sb_count++;
    return 0;
}

long hexa_scrollback_count(void) {
    if (g_active_tab < 0 || g_active_tab >= g_num_tabs) return 0;
    return (long)g_tabs[g_active_tab].sb_count;
}
