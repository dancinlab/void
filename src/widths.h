// widths.h — East-Asian width + emoji classification (FFI candidate)
//
// Source of truth: previously inline in src/void_main.hexa lines 546–605.
// Extracted per BUILD_SPEED_PLAN.md Phase B2 so that edits to the
// width/emoji tables rebuild in ~5s via clang instead of ~45min via
// the full hexa self-host transpile.
//
// Contract parity with hexa `is_wide_cjk(cp)`:
//   return 1 → cell should advance by 2 (East-Asian wide / fullwidth
//              / CJK / Hangul / emoji pictograph / SMP CJK Ext-B..G).
//   return 0 → cell should advance by 1 (ASCII / Latin / narrow).
//
// Additional emoji helpers are provided for future call-sites that
// need finer-grained classification (ZWJ sequences, skin-tone
// modifiers, VS-16 presentation selector). void_main.hexa does not
// invoke them yet; they are forward-compatible scaffolding so that a
// later hexa-side refactor can call through FFI without adding new C.

#ifndef HX_WIDTHS_H
#define HX_WIDTHS_H

#ifdef __cplusplus
extern "C" {
#endif

// Signatures use `long` to match the hexa FFI calling convention
// (hexa `int` → C `long`, see sys_pty.c). Don't change to `int` or
// the arm64 w0/x0 register passing will mismatch on the hexa side.

// Primary classifier — mirrors hexa `is_wide_cjk`.
// Returns 1 if `cp` occupies two terminal cells, else 0.
long hx_is_wide_cjk(long cp);

// Emoji skin-tone modifier (Fitzpatrick): U+1F3FB..U+1F3FF.
long hx_is_emoji_modifier(long cp);

// Zero-Width Joiner: U+200D.
long hx_is_zwj(long cp);

// Variation Selector-16 (emoji presentation): U+FE0F.
long hx_is_vs16(long cp);

// Supplementary Multilingual Plane CJK blocks (Ext-B..G):
// U+20000..U+2FFFD / U+30000..U+3FFFD.
long hx_is_smp_cjk(long cp);

#ifdef __cplusplus
}
#endif

#endif // HX_WIDTHS_H
