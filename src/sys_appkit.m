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
