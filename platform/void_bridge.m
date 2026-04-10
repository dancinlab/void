// void_bridge.m — Minimal Cocoa bridge for VOID terminal emulator
// Compile: clang -dynamiclib -framework Cocoa -framework CoreText -o libvoid_bridge.dylib void_bridge.m
//
// Provides C functions callable from hexa via extern FFI.
// All Cocoa/AppKit complexity is hidden here; hexa drives the main loop.

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>

// ── Global state ──

static NSApplication *app = nil;
static NSWindow *window = nil;
static NSView *contentView = nil;

// Terminal grid state (double-buffered)
#define MAX_ROWS 200
#define MAX_COLS 400

typedef struct {
    unichar ch;
    uint32_t fg;     // RGB packed
    uint32_t bg;     // RGB packed
    uint8_t flags;   // bold, italic, underline, etc.
} VoidCell;

static VoidCell grid[MAX_ROWS][MAX_COLS];
static int grid_rows = 24;
static int grid_cols = 80;
static int cursor_row = 0;
static int cursor_col = 0;
static int cursor_visible = 1;
static float cell_width = 0;
static float cell_height = 0;
static CTFontRef mono_font = NULL;
static int needs_display = 1;

// Input buffer (keys from user)
#define KEY_BUF_SIZE 4096
static char key_buf[KEY_BUF_SIZE];
static int key_buf_read = 0;
static int key_buf_write = 0;

static void key_buf_push(const char *data, int len) {
    for (int i = 0; i < len; i++) {
        key_buf[key_buf_write % KEY_BUF_SIZE] = data[i];
        key_buf_write++;
    }
}

// ── Custom NSView for terminal rendering ──

@interface VoidTermView : NSView
@end

@implementation VoidTermView

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }

static NSColor *color_from_index(int idx) {
    // Standard 16 ANSI colors
    static uint32_t ansi16[] = {
        0x000000, 0xCC0000, 0x00CC00, 0xCCCC00,
        0x0000CC, 0xCC00CC, 0x00CCCC, 0xCCCCCC,
        0x666666, 0xFF3333, 0x33FF33, 0xFFFF33,
        0x3333FF, 0xFF33FF, 0x33FFFF, 0xFFFFFF
    };
    if (idx < 0) idx = 7;
    if (idx < 16) {
        uint32_t c = ansi16[idx];
        return [NSColor colorWithRed:((c>>16)&0xFF)/255.0
                               green:((c>>8)&0xFF)/255.0
                                blue:(c&0xFF)/255.0 alpha:1.0];
    }
    if (idx < 256) {
        // 256-color: 16-231 = 6x6x6 cube, 232-255 = grayscale
        if (idx < 232) {
            int v = idx - 16;
            int r = v / 36, g = (v % 36) / 6, b = v % 6;
            return [NSColor colorWithRed:r ? (r*40+55)/255.0 : 0
                                   green:g ? (g*40+55)/255.0 : 0
                                    blue:b ? (b*40+55)/255.0 : 0 alpha:1.0];
        }
        int g = (idx - 232) * 10 + 8;
        return [NSColor colorWithRed:g/255.0 green:g/255.0 blue:g/255.0 alpha:1.0];
    }
    // TrueColor: 256 + R*65536 + G*256 + B
    int rgb = idx - 256;
    int r = rgb / 65536;
    int g = (rgb % 65536) / 256;
    int b = rgb % 256;
    return [NSColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (!mono_font) return;

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];

    // Background
    [[NSColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:1.0] setFill];
    NSRectFill(dirtyRect);

    // Draw cells
    for (int r = 0; r < grid_rows; r++) {
        float y = r * cell_height;
        if (y + cell_height < dirtyRect.origin.y || y > dirtyRect.origin.y + dirtyRect.size.height)
            continue;

        for (int c = 0; c < grid_cols; c++) {
            float x = c * cell_width;
            VoidCell *cell = &grid[r][c];

            // Cell background
            int bg = cell->bg;
            int fg = cell->fg;
            if (cell->flags & 8) { // inverse
                int tmp = bg; bg = fg; fg = tmp;
            }

            NSColor *bgColor = color_from_index(bg);
            if (bg != 0) { // skip default black bg
                [bgColor setFill];
                NSRectFill(NSMakeRect(x, y, cell_width, cell_height));
            }

            if (cell->ch <= ' ') continue;

            // Text attributes
            NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
            CTFontRef drawFont = mono_font;
            if (cell->flags & 1) { // bold
                drawFont = CTFontCreateCopyWithSymbolicTraits(mono_font, 0, NULL, kCTFontBoldTrait, kCTFontBoldTrait);
                if (!drawFont) drawFont = mono_font;
            }
            attrs[(id)kCTFontAttributeName] = (__bridge id)drawFont;
            attrs[(id)kCTForegroundColorAttributeName] = (__bridge id)[color_from_index(fg) CGColor];

            if (cell->flags & 4) { // underline
                attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
            }
            if (cell->flags & 32) { // strikethrough
                attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
            }

            unichar uch = cell->ch;
            NSString *str = [NSString stringWithCharacters:&uch length:1];
            NSAttributedString *astr = [[NSAttributedString alloc] initWithString:str attributes:attrs];

            // Draw
            CGFloat baseline = y + cell_height - CTFontGetDescent(drawFont) - 2;
            [astr drawAtPoint:NSMakePoint(x, y + 2)];

            if (drawFont != mono_font) CFRelease(drawFont);
        }
    }

    // Cursor
    if (cursor_visible && cursor_row < grid_rows && cursor_col < grid_cols) {
        float cx = cursor_col * cell_width;
        float cy = cursor_row * cell_height;
        [[NSColor colorWithRed:0.8 green:0.8 blue:0.9 alpha:0.7] setFill];
        NSRectFill(NSMakeRect(cx, cy, cell_width, cell_height));
    }
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event characters];
    if (!chars.length) return;

    // Handle special keys
    unsigned short keyCode = [event keyCode];
    NSEventModifierFlags mods = [event modifierFlags];

    // Check for Ctrl+key combinations
    if (mods & NSEventModifierFlagControl) {
        NSString *charsIgnoring = [event charactersIgnoringModifiers];
        if (charsIgnoring.length > 0) {
            unichar ch = [charsIgnoring characterAtIndex:0];
            if (ch >= 'a' && ch <= 'z') {
                char ctrl = ch - 'a' + 1;
                key_buf_push(&ctrl, 1);
                return;
            }
        }
    }

    // Function keys / arrow keys
    unichar ch = [chars characterAtIndex:0];
    switch (ch) {
        case NSUpArrowFunctionKey:    key_buf_push("\033[A", 3); return;
        case NSDownArrowFunctionKey:  key_buf_push("\033[B", 3); return;
        case NSRightArrowFunctionKey: key_buf_push("\033[C", 3); return;
        case NSLeftArrowFunctionKey:  key_buf_push("\033[D", 3); return;
        case NSHomeFunctionKey:       key_buf_push("\033[H", 3); return;
        case NSEndFunctionKey:        key_buf_push("\033[F", 3); return;
        case NSPageUpFunctionKey:     key_buf_push("\033[5~", 4); return;
        case NSPageDownFunctionKey:   key_buf_push("\033[6~", 4); return;
        case NSDeleteFunctionKey:     key_buf_push("\033[3~", 4); return;
        case NSF1FunctionKey:         key_buf_push("\033OP", 3); return;
        case NSF2FunctionKey:         key_buf_push("\033OQ", 3); return;
        case NSF3FunctionKey:         key_buf_push("\033OR", 3); return;
        case NSF4FunctionKey:         key_buf_push("\033OS", 3); return;
    }

    // Regular characters
    const char *utf8 = [chars UTF8String];
    key_buf_push(utf8, (int)strlen(utf8));
}

- (void)flagsChanged:(NSEvent *)event {
    // Ignore modifier-only events
}

@end

// ── Delegate to handle window close ──

static int app_should_quit = 0;

@interface VoidAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation VoidAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification { app_should_quit = 1; }
- (void)windowWillClose:(NSNotification *)notification { app_should_quit = 1; }
@end

static VoidAppDelegate *delegate = nil;

// ══════════════════════════════════════════════════════════════
// Public C API — called from hexa via extern FFI
// ══════════════════════════════════════════════════════════════

int void_app_init(int rows, int cols, int font_size) {
    @autoreleasepool {
        app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        delegate = [[VoidAppDelegate alloc] init];
        [app setDelegate:delegate];

        // Setup font and cell metrics
        mono_font = CTFontCreateWithName(CFSTR("MesloLGS-NF-Regular"), font_size, NULL);
        if (!mono_font) {
            mono_font = CTFontCreateWithName(CFSTR("Menlo-Regular"), font_size, NULL);
        }
        if (!mono_font) {
            mono_font = CTFontCreateWithName(CFSTR("Monaco"), font_size, NULL);
        }

        // Measure cell size using 'M'
        UniChar m_ch = 'M';
        CGGlyph glyph;
        CTFontGetGlyphsForCharacters(mono_font, &m_ch, &glyph, 1);
        CGSize advance;
        CTFontGetAdvancesForGlyphs(mono_font, kCTFontOrientationHorizontal, &glyph, &advance, 1);
        cell_width = advance.width;
        cell_height = CTFontGetAscent(mono_font) + CTFontGetDescent(mono_font) + CTFontGetLeading(mono_font) + 2;

        grid_rows = rows;
        grid_cols = cols;

        // Clear grid
        memset(grid, 0, sizeof(grid));
        for (int r = 0; r < MAX_ROWS; r++)
            for (int c = 0; c < MAX_COLS; c++) {
                grid[r][c].ch = ' ';
                grid[r][c].fg = 7;
            }

        float win_w = cell_width * cols;
        float win_h = cell_height * rows;

        NSRect frame = NSMakeRect(100, 100, win_w, win_h);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:style
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
        [window setTitle:@"VOID"];
        [window setDelegate:delegate];
        [window setMinSize:NSMakeSize(cell_width * 20, cell_height * 5)];

        // Dark appearance
        if (@available(macOS 10.14, *)) {
            [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        }
        [window setBackgroundColor:[NSColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:1.0]];

        contentView = [[VoidTermView alloc] initWithFrame:frame];
        [window setContentView:contentView];
        [window makeFirstResponder:contentView];
        [window makeKeyAndOrderFront:nil];

        [app activateIgnoringOtherApps:YES];

        // Create menu bar
        NSMenu *menubar = [[NSMenu alloc] init];
        NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
        [menubar addItem:appMenuItem];
        [app setMainMenu:menubar];

        NSMenu *appMenu = [[NSMenu alloc] init];
        [appMenu addItemWithTitle:@"Quit VOID" action:@selector(terminate:) keyEquivalent:@"q"];
        [appMenuItem setSubmenu:appMenu];
    }
    return 0;
}

void void_app_set_title(const char *title) {
    @autoreleasepool {
        [window setTitle:[NSString stringWithUTF8String:title]];
    }
}

// Set a single cell in the grid
void void_app_set_cell(int row, int col, int ch, int fg, int bg, int flags) {
    if (row < 0 || row >= MAX_ROWS || col < 0 || col >= MAX_COLS) return;
    grid[row][col].ch = (unichar)ch;
    grid[row][col].fg = fg;
    grid[row][col].bg = bg;
    grid[row][col].flags = flags;
}

// Set cursor position
void void_app_set_cursor(int row, int col, int visible) {
    cursor_row = row;
    cursor_col = col;
    cursor_visible = visible;
}

// Trigger a redraw
void void_app_flush(void) {
    @autoreleasepool {
        [contentView setNeedsDisplay:YES];
    }
}

// Process pending Cocoa events (non-blocking)
// Returns 1 if app should quit, 0 otherwise
int void_app_poll(void) {
    @autoreleasepool {
        while (1) {
            NSEvent *event = [app nextEventMatchingMask:NSEventMaskAny
                                             untilDate:nil
                                                inMode:NSDefaultRunLoopMode
                                               dequeue:YES];
            if (!event) break;
            [app sendEvent:event];
            [app updateWindows];
        }
    }
    return app_should_quit;
}

// Read pending keyboard input
// Returns number of bytes read (0 if none)
int void_app_read_keys(char *buf, int max_len) {
    int available = key_buf_write - key_buf_read;
    if (available <= 0) return 0;
    if (available > max_len) available = max_len;
    for (int i = 0; i < available; i++) {
        buf[i] = key_buf[key_buf_read % KEY_BUF_SIZE];
        key_buf_read++;
    }
    return available;
}

// Get current grid dimensions based on window size
int void_app_get_rows(void) {
    if (!window || cell_height <= 0) return grid_rows;
    NSRect frame = [[window contentView] frame];
    return (int)(frame.size.height / cell_height);
}

int void_app_get_cols(void) {
    if (!window || cell_width <= 0) return grid_cols;
    NSRect frame = [[window contentView] frame];
    return (int)(frame.size.width / cell_width);
}

// Get cell metrics
int void_app_cell_width(void) { return (int)(cell_width * 100); }
int void_app_cell_height(void) { return (int)(cell_height * 100); }
