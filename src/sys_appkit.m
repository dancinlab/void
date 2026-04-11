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
#include <util.h>

#define TERM_MAX_ROWS 200
#define TERM_MAX_COLS 400
#define MAX_TABS 20
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
static int g_term_quit = 0;

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
    static uint32_t a16[] = {
        0x000000,0xCC0000,0x00CC00,0xCCCC00,
        0x0000CC,0xCC00CC,0x00CCCC,0xCCCCCC,
        0x666666,0xFF3333,0x33FF33,0xFFFF33,
        0x3333FF,0xFF33FF,0x33FFFF,0xFFFFFF
    };
    if (idx < 0) idx = 7;
    if (idx < 16) {
        uint32_t c = a16[idx];
        return [NSColor colorWithRed:((c>>16)&0xFF)/255.0
                               green:((c>>8)&0xFF)/255.0
                                blue:(c&0xFF)/255.0 alpha:1.0];
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
    NSRect bounds = [self bounds];

    // ── Tab bar (left panel) ──
    [[NSColor colorWithRed:0.10 green:0.10 blue:0.14 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0, 0, TAB_BAR_W, bounds.size.height));

    // Separator line
    [[NSColor colorWithRed:0.25 green:0.25 blue:0.35 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(TAB_BAR_W - 1, 0, 1, bounds.size.height));

    NSFont *tabFont = [NSFont systemFontOfSize:11];
    for (int t = 0; t < g_num_tabs; t++) {
        float ty = 4 + t * TAB_ROW_H;
        // Active tab highlight
        if (t == g_active_tab) {
            [[NSColor colorWithRed:0.20 green:0.20 blue:0.30 alpha:1.0] setFill];
            NSRectFill(NSMakeRect(0, ty, TAB_BAR_W - 1, TAB_ROW_H));
            // Accent bar
            [[NSColor colorWithRed:0.45 green:0.45 blue:0.95 alpha:1.0] setFill];
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
                    ? [NSColor colorWithRed:0.9 green:0.9 blue:1.0 alpha:1.0]
                    : [NSColor colorWithRed:0.5 green:0.5 blue:0.6 alpha:1.0]
        };
        [title drawAtPoint:NSMakePoint(10, ty + 6) withAttributes:attrs];
    }

    // ── Terminal grid (right of tab bar) ──
    float ox = TAB_BAR_W;
    [[NSColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(ox, 0, bounds.size.width - ox, bounds.size.height));

    for (int r = 0; r < g_term_rows; r++) {
        float y = r * g_term_ch;
        if (y + g_term_ch < dirtyRect.origin.y ||
            y > dirtyRect.origin.y + dirtyRect.size.height) continue;
        for (int c = 0; c < g_term_cols; c++) {
            float x = ox + c * g_term_cw;
            TermCell *cell = &g_term_grid[r][c];
            int bg = cell->bg, fg = cell->fg;
            if (cell->flags & 8) { int t = bg; bg = fg; fg = t; }
            if (bg != 0) {
                [term_color(bg) setFill];
                NSRectFill(NSMakeRect(x, y, g_term_cw, g_term_ch));
            }
            if (cell->ch <= ' ') continue;

            NSMutableDictionary *a = [NSMutableDictionary dictionary];
            CTFontRef df = g_term_font;
            if (cell->flags & 1) {
                CTFontRef bf = CTFontCreateCopyWithSymbolicTraits(
                    g_term_font, 0, NULL, kCTFontBoldTrait, kCTFontBoldTrait);
                if (bf) df = bf;
            }
            a[(id)kCTFontAttributeName] = (__bridge id)df;
            a[(id)kCTForegroundColorAttributeName] = (__bridge id)[term_color(fg) CGColor];
            if (cell->flags & 4) a[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);

            unichar uch = cell->ch;
            NSString *s = [NSString stringWithCharacters:&uch length:1];
            NSAttributedString *as = [[NSAttributedString alloc] initWithString:s attributes:a];
            [as drawAtPoint:NSMakePoint(x, y + 2)];
            if (df != g_term_font) CFRelease(df);
        }
    }
    // Cursor
    if (g_term_cur_vis && g_term_cur_row < g_term_rows && g_term_cur_col < g_term_cols) {
        [[NSColor colorWithRed:0.8 green:0.8 blue:0.9 alpha:0.7] setFill];
        NSRectFill(NSMakeRect(ox + g_term_cur_col * g_term_cw,
                              g_term_cur_row * g_term_ch, g_term_cw, g_term_ch));
    }
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
            [self setNeedsDisplay:YES];
        }
    }
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event characters];
    if (!chars.length) return;
    NSEventModifierFlags mods = [event modifierFlags];

    // Cmd+key shortcuts
    if (mods & NSEventModifierFlagCommand) {
        NSString *raw = [event charactersIgnoringModifiers];
        if (raw.length > 0) {
            unichar ch = [raw characterAtIndex:0];
            if (ch == 't') { g_tab_cmd = 1; return; } // Cmd+T new tab
            if (ch == 'w') { g_tab_cmd = 2; return; } // Cmd+W close tab
            if (ch == 'q') { g_term_quit = 1; return; } // Cmd+Q quit
        }
        return; // Don't send other Cmd+ combos to PTY
    }

    // Ctrl+key
    if (mods & NSEventModifierFlagControl) {
        NSString *raw = [event charactersIgnoringModifiers];
        if (raw.length > 0) {
            unichar ch = [raw characterAtIndex:0];
            if (ch >= 'a' && ch <= 'z') {
                char ctrl = ch - 'a' + 1;
                term_key_push(&ctrl, 1);
                return;
            }
        }
    }

    unichar ch = [chars characterAtIndex:0];
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

long hexa_appkit_init_term(long rows, long cols, long font_size) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        g_term_delegate = [[HexaTermDelegate alloc] init];
        [app setDelegate:g_term_delegate];

        g_term_font = CTFontCreateWithName(CFSTR("Menlo-Regular"), font_size, NULL);
        if (!g_term_font) g_term_font = CTFontCreateWithName(CFSTR("Monaco"), font_size, NULL);

        UniChar mc = 'M';
        CGGlyph gl;
        CTFontGetGlyphsForCharacters(g_term_font, &mc, &gl, 1);
        CGSize adv;
        CTFontGetAdvancesForGlyphs(g_term_font, kCTFontOrientationHorizontal, &gl, &adv, 1);
        g_term_cw = adv.width;
        g_term_ch = CTFontGetAscent(g_term_font) + CTFontGetDescent(g_term_font) +
                    CTFontGetLeading(g_term_font) + 2;
        g_term_rows = (int)rows;
        g_term_cols = (int)cols;

        tab_clear_grid(g_term_grid);

        float ww = TAB_BAR_W + g_term_cw * cols;
        float wh = g_term_ch * rows;
        NSRect frame = NSMakeRect(100, 100, ww, wh);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        g_window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                                 backing:NSBackingStoreBuffered defer:NO];
        [g_window setTitle:@"VOID"];
        [g_window setDelegate:g_term_delegate];
        [g_window setMinSize:NSMakeSize(TAB_BAR_W + g_term_cw * 20, g_term_ch * 5)];
        if (@available(macOS 10.14, *))
            [g_window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [g_window setBackgroundColor:[NSColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:1.0]];

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
    // Get child pid from the forkpty (stored in hexa_sh_child_pid via sys_pty.c)
    // Actually we do it ourselves here:
    g_tabs[idx].pid = 0; // Will be set properly
    snprintf(g_tabs[idx].title, sizeof(g_tabs[idx].title), "");
    tab_clear_grid(g_tabs[idx].grid);
    g_tabs[idx].cur_row = 0;
    g_tabs[idx].cur_col = 0;

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

    // Shift tabs down
    for (int i = (int)idx; i < g_num_tabs - 1; i++) {
        g_tabs[i] = g_tabs[i + 1];
    }
    g_num_tabs--;

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

long hexa_appkit_term_poll(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        while (1) {
            NSEvent *ev = [app nextEventMatchingMask:NSEventMaskAny
                                           untilDate:nil
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES];
            if (!ev) break;
            [app sendEvent:ev];
            [app updateWindows];
        }
    }
    return g_term_quit;
}

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
