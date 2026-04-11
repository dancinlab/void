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
// void_main.hexa API — full terminal bridge
// ══════════════════════════════════════════════════════════════════

#define TERM_MAX_ROWS 200
#define TERM_MAX_COLS 400

typedef struct {
    unichar ch;
    int fg, bg, flags;
} TermCell;

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

// ── HexaTermView ──

@interface HexaTermView : NSView
@end

@implementation HexaTermView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    if (!g_term_font) return;
    [[NSColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:1.0] setFill];
    NSRectFill(dirtyRect);

    for (int r = 0; r < g_term_rows; r++) {
        float y = r * g_term_ch;
        if (y + g_term_ch < dirtyRect.origin.y ||
            y > dirtyRect.origin.y + dirtyRect.size.height) continue;
        for (int c = 0; c < g_term_cols; c++) {
            float x = c * g_term_cw;
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
        NSRectFill(NSMakeRect(g_term_cur_col * g_term_cw,
                              g_term_cur_row * g_term_ch, g_term_cw, g_term_ch));
    }
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event characters];
    if (!chars.length) return;
    NSEventModifierFlags mods = [event modifierFlags];
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

// App delegate for terminal
@interface HexaTermDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end
@implementation HexaTermDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }
- (void)applicationWillTerminate:(NSNotification *)n { g_term_quit = 1; }
- (void)windowWillClose:(NSNotification *)n { g_term_quit = 1; }
@end

static HexaTermDelegate *g_term_delegate = nil;

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

        for (int r = 0; r < TERM_MAX_ROWS; r++)
            for (int c = 0; c < TERM_MAX_COLS; c++) {
                g_term_grid[r][c].ch = ' ';
                g_term_grid[r][c].fg = 7;
                g_term_grid[r][c].bg = 0;
                g_term_grid[r][c].flags = 0;
            }

        float ww = g_term_cw * cols, wh = g_term_ch * rows;
        NSRect frame = NSMakeRect(100, 100, ww, wh);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        g_window = [[NSWindow alloc] initWithContentRect:frame styleMask:style
                                                 backing:NSBackingStoreBuffered defer:NO];
        [g_window setTitle:@"VOID"];
        [g_window setDelegate:g_term_delegate];
        [g_window setMinSize:NSMakeSize(g_term_cw * 20, g_term_ch * 5)];
        if (@available(macOS 10.14, *))
            [g_window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        [g_window setBackgroundColor:[NSColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:1.0]];

        NSView *tv = [[HexaTermView alloc] initWithFrame:frame];
        [g_window setContentView:tv];
        [g_window makeFirstResponder:tv];
        [g_window makeKeyAndOrderFront:nil];

        NSMenu *mb = [[NSMenu alloc] init];
        NSMenuItem *mi = [[NSMenuItem alloc] init];
        [mb addItem:mi];
        [app setMainMenu:mb];
        NSMenu *am = [[NSMenu alloc] init];
        [am addItemWithTitle:@"Quit VOID" action:@selector(terminate:) keyEquivalent:@"q"];
        [mi setSubmenu:am];

        [app finishLaunching];
        [app activateIgnoringOtherApps:YES];
    }
    return 0;
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

long hexa_appkit_term_read_keys(long buf_ptr, long max_len) {
    char *buf = (char*)(uintptr_t)buf_ptr;
    int avail = g_term_kw - g_term_kr;
    if (avail <= 0) return 0;
    if (avail > (int)max_len) avail = (int)max_len;
    for (int i = 0; i < avail; i++) {
        buf[i] = g_term_keys[g_term_kr % TERM_KEY_SIZE];
        g_term_kr++;
    }
    return (long)avail;
}

// Read pending keys from AppKit and write directly to PTY master.
// No pointer crosses FFI boundary. Returns bytes forwarded.
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

void hexa_appkit_term_set_title(const char *title) {
    if (!title) return;
    @autoreleasepool {
        [g_window setTitle:[NSString stringWithUTF8String:title]];
    }
}

long hexa_appkit_term_get_rows(void) {
    if (!g_window || g_term_ch <= 0) return g_term_rows;
    NSRect f = [[g_window contentView] frame];
    return (long)(f.size.height / g_term_ch);
}

long hexa_appkit_term_get_cols(void) {
    if (!g_window || g_term_cw <= 0) return g_term_cols;
    NSRect f = [[g_window contentView] frame];
    return (long)(f.size.width / g_term_cw);
}

// OSC title buffer — hexa pushes bytes, then apply sets window title
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
    if (!g_window) return;
    @autoreleasepool {
        [g_window setTitle:[NSString stringWithUTF8String:g_term_title_buf]];
    }
}
