// void_bridge_metal.m — Metal-accelerated Cocoa bridge for VOID terminal emulator
// Compile:
//   clang -dynamiclib -framework Metal -framework MetalKit -framework Cocoa \
//         -framework CoreText -framework QuartzCore \
//         -o lib/libvoid_bridge.dylib platform/void_bridge_metal.m
//
// Drop-in replacement for void_bridge.m — same C function signatures.
// Architecture: glyph atlas + cell buffer + instanced draw (like Alacritty/Ghostty).

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>
#include <string.h>

// ── Constants ──

#define MAX_ROWS 200
#define MAX_COLS 400
#define MAX_CELLS (MAX_ROWS * MAX_COLS)

// Glyph atlas layout: 16 columns × 6 rows = 96 slots (ASCII 32..127)
// Plus extra rows for box-drawing (U+2500..U+257F = 128 chars → 8 more rows)
#define ATLAS_COLS 16
#define ATLAS_ROWS_ASCII 6
#define ATLAS_ROWS_BOX 8
#define ATLAS_ROWS_TOTAL (ATLAS_ROWS_ASCII + ATLAS_ROWS_BOX)
#define ATLAS_GLYPH_COUNT (ATLAS_COLS * ATLAS_ROWS_TOTAL)

// Box-drawing range
#define BOX_DRAW_START 0x2500
#define BOX_DRAW_END   0x257F
#define BOX_DRAW_COUNT (BOX_DRAW_END - BOX_DRAW_START + 1)

// ── GPU cell data (must match shader) ──

typedef struct {
    uint32_t ch_index;  // glyph atlas index (0 = space)
    uint32_t fg;        // packed color index/truecolor
    uint32_t bg;        // packed color index/truecolor
    uint32_t flags;     // bold/italic/underline/inverse/strikethrough
} GPUCellData;

// ── Uniform data ──

typedef struct {
    float grid_cols;
    float grid_rows;
    float cell_w;       // in pixels
    float cell_h;       // in pixels
    float viewport_w;   // in pixels
    float viewport_h;   // in pixels
    float cursor_row;
    float cursor_col;
    float cursor_visible;
    float _pad[3];
} Uniforms;

// ── Global state ──

static NSApplication *app = nil;
static NSWindow *window = nil;
static MTKView *mtkView = nil;

static id<MTLDevice> device = nil;
static id<MTLCommandQueue> commandQueue = nil;
static id<MTLRenderPipelineState> pipelineState = nil;
static id<MTLTexture> atlasTexture = nil;
static id<MTLBuffer> cellBuffer = nil;
static id<MTLBuffer> uniformBuffer = nil;

static GPUCellData cpuCells[MAX_CELLS];
static int grid_rows = 24;
static int grid_cols = 80;
static int cursor_row = 0;
static int cursor_col = 0;
static int cursor_visible = 1;
static float cell_width = 0;   // in points (1x)
static float cell_height = 0;  // in points (1x)
static float backing_scale = 2.0; // Retina scale factor
static CTFontRef mono_font = NULL;
static int needs_upload = 1;

// Glyph-to-atlas mapping: for a given unichar, what atlas index?
// ASCII 32..126 → indices 0..94
// Box drawing 0x2500..0x257F → indices 96..223
// Anything else → 0 (space)
static inline uint32_t glyph_atlas_index(int ch) {
    if (ch >= 32 && ch <= 126) return (uint32_t)(ch - 32);
    if (ch >= BOX_DRAW_START && ch <= BOX_DRAW_END)
        return (uint32_t)(96 + (ch - BOX_DRAW_START));
    if (ch < 32) return 0; // control chars → space
    return 0; // unmapped → space
}

// ── Input buffer ──

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

// ── ANSI color table ──

static uint32_t ansi16[] = {
    0x000000, 0xCC0000, 0x00CC00, 0xCCCC00,
    0x0000CC, 0xCC00CC, 0x00CCCC, 0xCCCCCC,
    0x666666, 0xFF3333, 0x33FF33, 0xFFFF33,
    0x3333FF, 0xFF33FF, 0x33FFFF, 0xFFFFFF
};

static void color_unpack(int idx, float *r, float *g, float *b) {
    if (idx < 0) idx = 7;
    uint32_t rgb;
    if (idx < 16) {
        rgb = ansi16[idx];
    } else if (idx < 232) {
        int v = idx - 16;
        int ri = v / 36, gi = (v % 36) / 6, bi = v % 6;
        int rc = ri ? (ri * 40 + 55) : 0;
        int gc = gi ? (gi * 40 + 55) : 0;
        int bc = bi ? (bi * 40 + 55) : 0;
        rgb = (rc << 16) | (gc << 8) | bc;
    } else if (idx < 256) {
        int g_ = (idx - 232) * 10 + 8;
        rgb = (g_ << 16) | (g_ << 8) | g_;
    } else {
        // TrueColor: 256 + R*65536 + G*256 + B
        rgb = idx - 256;
    }
    *r = ((rgb >> 16) & 0xFF) / 255.0f;
    *g = ((rgb >> 8) & 0xFF) / 255.0f;
    *b = (rgb & 0xFF) / 255.0f;
}

// Pack color index into a uint32 that the shader can decode.
// We encode R/G/B in the upper 24 bits so the shader just reads float3.
static uint32_t color_pack_rgb(int idx) {
    float r, g, b;
    color_unpack(idx, &r, &g, &b);
    uint32_t ri = (uint32_t)(r * 255.0f);
    uint32_t gi = (uint32_t)(g * 255.0f);
    uint32_t bi = (uint32_t)(b * 255.0f);
    return (ri << 16) | (gi << 8) | bi;
}

// ── Metal shaders (compiled at runtime) ──

static NSString *shaderSource = @"\n\
#include <metal_stdlib>\n\
using namespace metal;\n\
\n\
struct CellData {\n\
    uint ch_index;\n\
    uint fg;\n\
    uint bg;\n\
    uint flags;\n\
};\n\
\n\
struct Uniforms {\n\
    float grid_cols;\n\
    float grid_rows;\n\
    float cell_w;\n\
    float cell_h;\n\
    float viewport_w;\n\
    float viewport_h;\n\
    float cursor_row;\n\
    float cursor_col;\n\
    float cursor_visible;\n\
    float _pad0;\n\
    float _pad1;\n\
    float _pad2;\n\
};\n\
\n\
struct VertexOut {\n\
    float4 position [[position]];\n\
    float2 texCoord;\n\
    float3 fgColor;\n\
    float3 bgColor;\n\
    float isCursor;\n\
    uint flags;\n\
};\n\
\n\
constant float2 quad_verts[6] = {\n\
    float2(0,0), float2(1,0), float2(0,1),\n\
    float2(1,0), float2(1,1), float2(0,1)\n\
};\n\
\n\
float3 unpack_color(uint c) {\n\
    return float3(\n\
        float((c >> 16) & 0xFF) / 255.0,\n\
        float((c >> 8)  & 0xFF) / 255.0,\n\
        float( c        & 0xFF) / 255.0\n\
    );\n\
}\n\
\n\
vertex VertexOut vertex_main(\n\
    uint vid [[vertex_id]],\n\
    uint iid [[instance_id]],\n\
    constant CellData *cells [[buffer(0)]],\n\
    constant Uniforms &u [[buffer(1)]]\n\
) {\n\
    VertexOut out;\n\
    \n\
    int cols = int(u.grid_cols);\n\
    int row = int(iid) / cols;\n\
    int col = int(iid) % cols;\n\
    \n\
    float2 corner = quad_verts[vid];\n\
    \n\
    // Pixel position\n\
    float px = (float(col) + corner.x) * u.cell_w;\n\
    float py = (float(row) + corner.y) * u.cell_h;\n\
    \n\
    // To NDC: x in [0, viewport_w] -> [-1, 1], y in [0, viewport_h] -> [1, -1] (flipped)\n\
    out.position = float4(\n\
        (px / u.viewport_w) * 2.0 - 1.0,\n\
        1.0 - (py / u.viewport_h) * 2.0,\n\
        0.0, 1.0\n\
    );\n\
    \n\
    CellData cell = cells[iid];\n\
    uint ch_idx = cell.ch_index;\n\
    \n\
    // Atlas UV: 16 cols × 14 rows\n\
    float atlas_col = float(ch_idx % 16u);\n\
    float atlas_row = float(ch_idx / 16u);\n\
    float atlas_cols = 16.0;\n\
    float atlas_rows = 14.0;\n\
    \n\
    float u0 = (atlas_col + corner.x) / atlas_cols;\n\
    float v0 = (atlas_row + corner.y) / atlas_rows;\n\
    out.texCoord = float2(u0, v0);\n\
    \n\
    uint flags = cell.flags;\n\
    uint fg_raw = cell.fg;\n\
    uint bg_raw = cell.bg;\n\
    \n\
    // Inverse (flag bit 3)\n\
    if (flags & 8u) {\n\
        uint tmp = fg_raw;\n\
        fg_raw = bg_raw;\n\
        bg_raw = tmp;\n\
    }\n\
    \n\
    out.fgColor = unpack_color(fg_raw);\n\
    out.bgColor = unpack_color(bg_raw);\n\
    out.flags = flags;\n\
    \n\
    // Cursor detection\n\
    out.isCursor = (u.cursor_visible > 0.5 && row == int(u.cursor_row) && col == int(u.cursor_col)) ? 1.0 : 0.0;\n\
    \n\
    return out;\n\
}\n\
\n\
fragment float4 fragment_main(\n\
    VertexOut in [[stage_in]],\n\
    texture2d<float> atlas [[texture(0)]]\n\
) {\n\
    constexpr sampler s(mag_filter::nearest, min_filter::nearest);\n\
    float4 texel = atlas.sample(s, in.texCoord);\n\
    float alpha = texel.r;  // single-channel alpha from CoreText rasterization\n\
    \n\
    float3 color = mix(in.bgColor, in.fgColor, alpha);\n\
    \n\
    // Underline (flag bit 2): draw bottom 1px line\n\
    // We detect this by checking if we're near the bottom of the cell\n\
    // texCoord.y within the cell goes 0..1, underline at ~0.92+\n\
    if ((in.flags & 4u) && in.texCoord.y > 0.0) {\n\
        // Approximate bottom of cell\n\
        float cell_v = fract(in.texCoord.y * 14.0);\n\
        if (cell_v > 0.9) {\n\
            color = in.fgColor;\n\
        }\n\
    }\n\
    \n\
    // Strikethrough (flag bit 5): middle line\n\
    if ((in.flags & 32u) && in.texCoord.y > 0.0) {\n\
        float cell_v = fract(in.texCoord.y * 14.0);\n\
        if (cell_v > 0.45 && cell_v < 0.55) {\n\
            color = in.fgColor;\n\
        }\n\
    }\n\
    \n\
    // Cursor overlay\n\
    if (in.isCursor > 0.5) {\n\
        color = mix(color, float3(0.8, 0.8, 0.9), 0.7);\n\
    }\n\
    \n\
    return float4(color, 1.0);\n\
}\n\
";

// ── Glyph atlas creation ──

static void create_glyph_atlas(int cell_w, int cell_h) {
    // cell_w/cell_h are in Retina pixels (e.g., 2x on Retina)
    int tex_w = ATLAS_COLS * cell_w;
    int tex_h = ATLAS_ROWS_TOTAL * cell_h;

    // Create bitmap context (single channel — we use red channel as alpha)
    uint8_t *bitmap = (uint8_t *)calloc(tex_w * tex_h, 1);
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(
        bitmap, tex_w, tex_h, 8, tex_w,
        gray, (CGBitmapInfo)kCGImageAlphaNone
    );
    CGColorSpaceRelease(gray);

    if (!ctx) {
        free(bitmap);
        return;
    }

    // Scale context for Retina — draw at 2x
    CGContextScaleCTM(ctx, backing_scale, backing_scale);

    // White text on black background for alpha extraction
    CGContextSetGrayFillColor(ctx, 0.0, 1.0); // black bg
    CGContextFillRect(ctx, CGRectMake(0, 0, tex_w / backing_scale, tex_h / backing_scale));
    CGContextSetGrayFillColor(ctx, 1.0, 1.0); // white text

    // Enable antialiasing
    CGContextSetShouldAntialias(ctx, true);
    CGContextSetShouldSmoothFonts(ctx, true);

    CGFloat ascent = CTFontGetAscent(mono_font);
    CGFloat descent = CTFontGetDescent(mono_font);
    // Use 1x point-based cell size for glyph positioning (context is scaled)
    float pt_cell_w = cell_w / backing_scale;
    float pt_cell_h = cell_h / backing_scale;

    // Rasterize ASCII printable: 32..126 (indices 0..94)
    // Positions in points (context is scaled for Retina)
    for (int i = 0; i < 95; i++) {
        unichar ch = (unichar)(32 + i);
        float ax = (i % ATLAS_COLS) * pt_cell_w;
        float ay = (i / ATLAS_COLS) * pt_cell_h;
        float tex_h_pt = tex_h / backing_scale;

        // CoreGraphics has origin at bottom-left; we need to flip
        CGFloat gx = (CGFloat)ax;
        CGFloat gy = (CGFloat)(tex_h_pt - ay - pt_cell_h) + descent + 1;

        CFStringRef str = CFStringCreateWithCharacters(NULL, &ch, 1);
        CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(
            NULL, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
        );
        CFDictionarySetValue(attrs, kCTFontAttributeName, mono_font);

        // White foreground
        CGColorRef white = CGColorCreateGenericGray(1.0, 1.0);
        CFDictionarySetValue(attrs, kCTForegroundColorAttributeName, white);

        CFAttributedStringRef astr = CFAttributedStringCreate(NULL, str, attrs);
        CTLineRef line = CTLineCreateWithAttributedString(astr);

        CGContextSetTextPosition(ctx, gx, gy);
        CTLineDraw(line, ctx);

        CFRelease(line);
        CFRelease(astr);
        CGColorRelease(white);
        CFRelease(attrs);
        CFRelease(str);
    }

    // Rasterize box-drawing: U+2500..U+257F (indices 96..223)
    for (int i = 0; i < BOX_DRAW_COUNT; i++) {
        unichar ch = (unichar)(BOX_DRAW_START + i);
        int slot = 96 + i;
        float ax = (slot % ATLAS_COLS) * pt_cell_w;
        float ay = (slot / ATLAS_COLS) * pt_cell_h;
        float tex_h_pt = tex_h / backing_scale;

        CGFloat gx = (CGFloat)ax;
        CGFloat gy = (CGFloat)(tex_h_pt - ay - pt_cell_h) + descent + 1;

        CFStringRef str = CFStringCreateWithCharacters(NULL, &ch, 1);
        CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(
            NULL, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
        );
        CFDictionarySetValue(attrs, kCTFontAttributeName, mono_font);
        CGColorRef white = CGColorCreateGenericGray(1.0, 1.0);
        CFDictionarySetValue(attrs, kCTForegroundColorAttributeName, white);

        CFAttributedStringRef astr = CFAttributedStringCreate(NULL, str, attrs);
        CTLineRef line = CTLineCreateWithAttributedString(astr);

        // Check if font has this glyph; if not, skip (will render as space)
        CGGlyph glyph;
        BOOL hasGlyph = CTFontGetGlyphsForCharacters(mono_font, &ch, &glyph, 1);
        if (hasGlyph && glyph != 0) {
            CGContextSetTextPosition(ctx, gx, gy);
            CTLineDraw(line, ctx);
        }

        CFRelease(line);
        CFRelease(astr);
        CGColorRelease(white);
        CFRelease(attrs);
        CFRelease(str);
    }

    CGContextRelease(ctx);

    // Create Metal texture from bitmap
    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                     width:tex_w
                                    height:tex_h
                                 mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModeManaged;

    atlasTexture = [device newTextureWithDescriptor:desc];
    [atlasTexture replaceRegion:MTLRegionMake2D(0, 0, tex_w, tex_h)
                    mipmapLevel:0
                      withBytes:bitmap
                    bytesPerRow:tex_w];

    free(bitmap);
}

// ── MTKView delegate (renderer) ──

@interface VoidMetalRenderer : NSObject <MTKViewDelegate>
@end

@implementation VoidMetalRenderer

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // Handled by void_app_get_rows/cols polling
}

- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
        if (!pipelineState || !atlasTexture || !cellBuffer) return;

        int totalCells = grid_rows * grid_cols;
        if (totalCells <= 0 || totalCells > MAX_CELLS) return;

        // Upload cell data if dirty
        if (needs_upload) {
            memcpy([cellBuffer contents], cpuCells, totalCells * sizeof(GPUCellData));
            [cellBuffer didModifyRange:NSMakeRange(0, totalCells * sizeof(GPUCellData))];
            needs_upload = 0;
        }

        // Update uniforms — scale cell size by backing scale for Retina
        CGSize drawableSize = view.drawableSize;
        CGFloat scale = view.window.backingScaleFactor;
        if (scale < 1.0) scale = 1.0;
        Uniforms u;
        u.grid_cols = (float)grid_cols;
        u.grid_rows = (float)grid_rows;
        u.cell_w = (float)(cell_width * scale);
        u.cell_h = (float)(cell_height * scale);
        u.viewport_w = (float)drawableSize.width;
        u.viewport_h = (float)drawableSize.height;
        u.cursor_row = (float)cursor_row;
        u.cursor_col = (float)cursor_col;
        u.cursor_visible = cursor_visible ? 1.0f : 0.0f;
        u._pad[0] = u._pad[1] = u._pad[2] = 0.0f;
        memcpy([uniformBuffer contents], &u, sizeof(Uniforms));
        [uniformBuffer didModifyRange:NSMakeRange(0, sizeof(Uniforms))];

        id<MTLCommandBuffer> cmdBuf = [commandQueue commandBuffer];
        if (!cmdBuf) return;

        MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
        if (!rpd) return;

        // Dark background clear color
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0.07, 0.07, 0.10, 1.0);
        rpd.colorAttachments[0].loadAction = MTLLoadActionClear;

        id<MTLRenderCommandEncoder> enc = [cmdBuf renderCommandEncoderWithDescriptor:rpd];
        if (!enc) return;

        [enc setRenderPipelineState:pipelineState];
        [enc setVertexBuffer:cellBuffer offset:0 atIndex:0];
        [enc setVertexBuffer:uniformBuffer offset:0 atIndex:1];
        [enc setFragmentTexture:atlasTexture atIndex:0];

        // One instanced draw: 6 vertices per quad, totalCells instances
        [enc drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:totalCells];

        [enc endEncoding];
        [cmdBuf presentDrawable:view.currentDrawable];
        [cmdBuf commit];
    }
}

@end

static VoidMetalRenderer *renderer = nil;

// ── Event-handling view (subclass MTKView for key input) ──

@interface VoidMTKView : MTKView
@end

@implementation VoidMTKView

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event characters];
    if (!chars.length) return;

    NSEventModifierFlags mods = [event modifierFlags];

    // Cmd+key → VOID protocol escape sequences
    if (mods & NSEventModifierFlagCommand) {
        NSString *charsIgnoring = [event charactersIgnoringModifiers];
        if (charsIgnoring.length > 0) {
            unichar ch = [charsIgnoring characterAtIndex:0];
            const char *seq = NULL;
            switch (ch) {
                case 't': seq = "\033]777;key;cmd+t\007"; break;
                case 'w': seq = "\033]777;key;cmd+w\007"; break;
                case 'n': seq = "\033]777;key;cmd+n\007"; break;
                case '1': seq = "\033]777;key;cmd+1\007"; break;
                case '2': seq = "\033]777;key;cmd+2\007"; break;
                case '3': seq = "\033]777;key;cmd+3\007"; break;
                case '4': seq = "\033]777;key;cmd+4\007"; break;
                case '5': seq = "\033]777;key;cmd+5\007"; break;
                case '6': seq = "\033]777;key;cmd+6\007"; break;
                case '7': seq = "\033]777;key;cmd+7\007"; break;
                case '8': seq = "\033]777;key;cmd+8\007"; break;
                case '9': seq = "\033]777;key;cmd+9\007"; break;
                default: break;
            }
            if (seq) {
                key_buf_push(seq, (int)strlen(seq));
                return;
            }
            // Cmd+Q handled by menu / NSApp terminate
            if (ch == 'q') {
                [NSApp terminate:nil];
                return;
            }
        }
    }

    // Ctrl+key combinations
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

    // Alt/Option+key → ESC prefix
    if (mods & NSEventModifierFlagOption) {
        NSString *charsIgnoring = [event charactersIgnoringModifiers];
        if (charsIgnoring.length > 0) {
            const char esc = '\033';
            key_buf_push(&esc, 1);
            const char *utf8 = [charsIgnoring UTF8String];
            key_buf_push(utf8, (int)strlen(utf8));
            return;
        }
    }

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
        case NSF5FunctionKey:         key_buf_push("\033[15~", 5); return;
        case NSF6FunctionKey:         key_buf_push("\033[17~", 5); return;
        case NSF7FunctionKey:         key_buf_push("\033[18~", 5); return;
        case NSF8FunctionKey:         key_buf_push("\033[19~", 5); return;
        case NSF9FunctionKey:         key_buf_push("\033[20~", 5); return;
        case NSF10FunctionKey:        key_buf_push("\033[21~", 5); return;
        case NSF11FunctionKey:        key_buf_push("\033[23~", 5); return;
        case NSF12FunctionKey:        key_buf_push("\033[24~", 5); return;
    }

    // Regular characters
    const char *utf8 = [chars UTF8String];
    key_buf_push(utf8, (int)strlen(utf8));
}

- (void)flagsChanged:(NSEvent *)event {
    // Ignore modifier-only events
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    // Let Cmd+Q go through to menu
    NSEventModifierFlags mods = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (mods == NSEventModifierFlagCommand) {
        NSString *chars = [event charactersIgnoringModifiers];
        if (chars.length > 0 && [chars characterAtIndex:0] == 'q') {
            return NO; // let menu handle it
        }
    }
    // Intercept all other Cmd+key so they reach keyDown
    if (mods & NSEventModifierFlagCommand) {
        [self keyDown:event];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

@end

// ── Window delegate ──

static int app_should_quit = 0;

@interface VoidAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation VoidAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification { app_should_quit = 1; }
- (void)windowWillClose:(NSNotification *)notification { app_should_quit = 1; }

- (void)windowDidResize:(NSNotification *)notification {
    // Grid dimensions will be recalculated on next void_app_get_rows/cols call.
    // Mark cells dirty so the full grid is re-uploaded.
    needs_upload = 1;
}
@end

static VoidAppDelegate *delegate = nil;

// ── Setup Metal pipeline ──

static int setup_metal_pipeline(void) {
    NSError *error = nil;

    id<MTLLibrary> library = [device newLibraryWithSource:shaderSource
                                                  options:nil
                                                    error:&error];
    if (!library) {
        NSLog(@"VOID Metal: shader compile error: %@", error);
        return -1;
    }

    id<MTLFunction> vertFunc = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragFunc = [library newFunctionWithName:@"fragment_main"];
    if (!vertFunc || !fragFunc) {
        NSLog(@"VOID Metal: failed to find shader functions");
        return -1;
    }

    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = vertFunc;
    desc.fragmentFunction = fragFunc;
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    // Enable alpha blending (not strictly needed since we output alpha=1,
    // but future-proofing for transparency effects)
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    pipelineState = [device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (!pipelineState) {
        NSLog(@"VOID Metal: pipeline creation error: %@", error);
        return -1;
    }

    return 0;
}

// ══════════════════════════════════════════════════════════════
// Public C API — called from hexa via extern FFI
// ══════════════════════════════════════════════════════════════

int void_app_init(int rows, int cols, int font_size) {
    @autoreleasepool {
        app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        delegate = [[VoidAppDelegate alloc] init];
        [app setDelegate:delegate];

        // Setup font
        mono_font = CTFontCreateWithName(CFSTR("MesloLGS-NF-Regular"), font_size, NULL);
        if (!mono_font) {
            mono_font = CTFontCreateWithName(CFSTR("Menlo-Regular"), font_size, NULL);
        }
        if (!mono_font) {
            mono_font = CTFontCreateWithName(CFSTR("Monaco"), font_size, NULL);
        }
        if (!mono_font) {
            NSLog(@"VOID Metal: no suitable font found");
            return -1;
        }

        // Measure cell size using 'M'
        UniChar m_ch = 'M';
        CGGlyph glyph;
        CTFontGetGlyphsForCharacters(mono_font, &m_ch, &glyph, 1);
        CGSize advance;
        CTFontGetAdvancesForGlyphs(mono_font, kCTFontOrientationHorizontal, &glyph, &advance, 1);
        cell_width = ceilf(advance.width);
        cell_height = ceilf(CTFontGetAscent(mono_font) + CTFontGetDescent(mono_font) +
                            CTFontGetLeading(mono_font) + 2);

        grid_rows = rows;
        grid_cols = cols;

        // Init Metal device
        device = MTLCreateSystemDefaultDevice();
        if (!device) {
            NSLog(@"VOID Metal: no Metal device available");
            return -1;
        }
        commandQueue = [device newCommandQueue];

        // Detect Retina scale before creating atlas
        backing_scale = [[NSScreen mainScreen] backingScaleFactor];
        if (backing_scale < 1.0) backing_scale = 1.0;

        // Create glyph atlas at Retina resolution (2x on Retina)
        create_glyph_atlas((int)(cell_width * backing_scale), (int)(cell_height * backing_scale));
        if (!atlasTexture) {
            NSLog(@"VOID Metal: failed to create glyph atlas");
            return -1;
        }

        // Setup shader pipeline
        if (setup_metal_pipeline() != 0) {
            return -1;
        }

        // Create GPU buffers
        cellBuffer = [device newBufferWithLength:MAX_CELLS * sizeof(GPUCellData)
                                         options:MTLResourceStorageModeManaged];
        uniformBuffer = [device newBufferWithLength:sizeof(Uniforms)
                                            options:MTLResourceStorageModeManaged];

        // Init CPU cell array (space, fg=7 white, bg=0 black)
        for (int i = 0; i < MAX_CELLS; i++) {
            cpuCells[i].ch_index = 0;  // space
            cpuCells[i].fg = color_pack_rgb(7);
            cpuCells[i].bg = color_pack_rgb(0);
            cpuCells[i].flags = 0;
        }
        needs_upload = 1;

        // Create window
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

        // Create MTKView
        mtkView = [[VoidMTKView alloc] initWithFrame:frame device:device];
        mtkView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        mtkView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        mtkView.clearColor = MTLClearColorMake(0.07, 0.07, 0.10, 1.0);
        // We drive rendering manually from void_app_flush(), not a timer
        mtkView.paused = YES;
        mtkView.enableSetNeedsDisplay = YES;

        renderer = [[VoidMetalRenderer alloc] init];
        mtkView.delegate = renderer;

        [window setContentView:mtkView];
        [window makeFirstResponder:mtkView];
        [window makeKeyAndOrderFront:nil];

        // finishLaunching is required when driving the event loop manually
        // (without [NSApp run]). Without it, the window never appears on screen.
        [app finishLaunching];
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

void void_app_set_cell(int row, int col, int ch, int fg, int bg, int flags) {
    if (row < 0 || row >= MAX_ROWS || col < 0 || col >= MAX_COLS) return;
    int idx = row * grid_cols + col;
    if (idx < 0 || idx >= MAX_CELLS) return;

    cpuCells[idx].ch_index = glyph_atlas_index(ch);
    cpuCells[idx].fg = color_pack_rgb(fg);
    cpuCells[idx].bg = color_pack_rgb(bg);
    cpuCells[idx].flags = (uint32_t)flags;
    needs_upload = 1;
}

void void_app_set_cursor(int row, int col, int visible) {
    cursor_row = row;
    cursor_col = col;
    cursor_visible = visible;
    needs_upload = 1;
}

void void_app_flush(void) {
    @autoreleasepool {
        [mtkView setNeedsDisplay:YES];
        // Force immediate draw so we don't wait for next run loop iteration
        [mtkView display];
    }
}

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

int void_app_get_rows(void) {
    if (!window || cell_height <= 0) return grid_rows;
    @autoreleasepool {
        NSRect frame = [[window contentView] frame];
        int r = (int)(frame.size.height / cell_height);
        if (r > MAX_ROWS) r = MAX_ROWS;
        if (r < 1) r = 1;
        return r;
    }
}

int void_app_get_cols(void) {
    if (!window || cell_width <= 0) return grid_cols;
    @autoreleasepool {
        NSRect frame = [[window contentView] frame];
        int c = (int)(frame.size.width / cell_width);
        if (c > MAX_COLS) c = MAX_COLS;
        if (c < 1) c = 1;
        return c;
    }
}

// Legacy compatibility — cell metrics in hundredths of a pixel
int void_app_cell_width(void) { return (int)(cell_width * 100); }
int void_app_cell_height(void) { return (int)(cell_height * 100); }
