// widths.c — East-Asian width + emoji classification
//
// 1:1 port of src/void_main.hexa lines 546–605 (`wide_pages`,
// `is_wide_cjk_mixed`, `is_wide_cjk`). Bit-identical: the same cp in
// hexa and C must yield the same 0/1. Do NOT "improve" the logic here
// without updating both sides.
//
// Hot path (BMP): O(1) page-table lookup. 256 pages of 256 cp each.
//   0 = all narrow, 1 = all wide, 2 = mixed (fallback to range list).
//
// Non-BMP path: small sorted range list, linear scan (<= 3 entries).
// Linear beats binary-search setup cost at n=3.
//
// Build: `clang -O2 -c src/widths.c -o build/widths.o`
// Bench: see tests/bench_width.c

#include "widths.h"

#include <stdint.h>

// ── BMP page table (U+0000..U+FFFF) ─────────────────────────────────
// Source: void_main.hexa:556–573. Index = cp / 256. Values:
//   0 → page entirely narrow
//   1 → page entirely wide
//   2 → page mixed (resolve via wide_bmp_mixed below)
static const uint8_t wide_pages[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 2, 1,
    2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 2, 2,
};

// ── Mixed-page fallback (sorted, 10 ranges) ─────────────────────────
// Source: void_main.hexa:576–588. Covers only the 8 pages marked "2"
// in wide_pages (17, 46, 48, 77, 164, 215, 254, 255). Plus the two
// page-255 subranges (65280..65376, 65504..65510). Sorted ascending.
static const int32_t wide_bmp_mixed[][2] = {
    {  4352,  4447 },   // Hangul Jamo (page 17)
    { 11904, 12031 },   // CJK radicals (page 46)
    { 12288, 12350 },   // CJK symbols + ideographic space (page 48)
    { 12353, 12543 },   // Hiragana/Katakana (page 48)
    { 19712, 19903 },   // CJK Ext-A tail (page 77)
    { 41984, 42191 },   // Yi tail (page 164)
    { 55040, 55203 },   // Hangul Syllables tail (page 215)
    { 65072, 65103 },   // CJK Compat Forms (page 254)
    { 65280, 65376 },   // Fullwidth ASCII (page 255)
    { 65504, 65510 },   // Fullwidth symbols (page 255)
};
enum { WIDE_BMP_MIXED_N = (int)(sizeof(wide_bmp_mixed) / sizeof(wide_bmp_mixed[0])) };

// Non-BMP wide ranges are inlined in hx_is_wide_cjk below (only 3
// ranges, and keeping them as a table forces a pointer-chase that
// costs more at -O2 than three inline compares).

// ── BMP mixed-page fallback ─────────────────────────────────────────
// Small n (10) — linear scan beats binary search (branch-predictable,
// all ranges fit in one cache line). Caller already knows cp is in a
// "mixed" page, so we skip the initial `cp < first_range` shortcut.
static int is_wide_cjk_mixed(int cp) {
    for (int i = 0; i < WIDE_BMP_MIXED_N; i++) {
        if (cp < wide_bmp_mixed[i][0]) return 0;
        if (cp <= wide_bmp_mixed[i][1]) return 1;
    }
    return 0;
}

// ── Primary classifier ──────────────────────────────────────────────
// Branch ordering is tuned for terminal streams: ASCII dominates,
// then BMP CJK, then SMP/emoji. Reordering away from hexa source is
// intentional and semantically identical (see anchor tests in
// tests/bench_width.c).
int hx_is_wide_cjk(int cp) {
    // Fast path: ASCII / Latin / common scripts — vast majority of
    // real terminal input. Matches hexa `if cp < 4352 { return 0 }`.
    if ((unsigned)cp < 4352u) return 0;

    // BMP O(1) page-table lookup. This is the hot branch for mixed
    // CJK/Latin content — ~30% of realistic terminal streams.
    if ((unsigned)cp <= 65535u) {
        uint8_t tag = wide_pages[(unsigned)cp >> 8];
        if (tag < 2) return (int)tag;   // 0 → narrow, 1 → wide
        return is_wide_cjk_mixed(cp);
    }

    // Non-BMP: 3 ranges (emoji, CJK Ext-B..F, CJK Ext-G). Unrolled so
    // the compiler can schedule compares tightly; the linear scan
    // version stalls on loop-carried dependencies at -O2.
    if (cp < 126976)   return 0;
    if (cp <= 129791)  return 1;   // emoji + pictographs
    if (cp < 131072)   return 0;
    if (cp <= 196605)  return 1;   // CJK Ext-B..F
    if (cp < 196608)   return 0;
    if (cp <= 262141)  return 1;   // CJK Ext-G
    return 0;
}

// ── Emoji helpers (forward-compatible; not yet called from hexa) ────

// Fitzpatrick skin-tone modifiers (U+1F3FB EMOJI MODIFIER FITZPATRICK
// TYPE-1-2 .. U+1F3FF EMOJI MODIFIER FITZPATRICK TYPE-6).
int hx_is_emoji_modifier(int cp) {
    return (cp >= 0x1F3FB && cp <= 0x1F3FF) ? 1 : 0;
}

// ZERO WIDTH JOINER — glues emoji sequences into a single grapheme.
int hx_is_zwj(int cp) {
    return (cp == 0x200D) ? 1 : 0;
}

// VARIATION SELECTOR-16 — forces emoji presentation on dual-use cp.
int hx_is_vs16(int cp) {
    return (cp == 0xFE0F) ? 1 : 0;
}

// Supplementary Multilingual Plane CJK (Ext-B..G, as classified in
// void_main.hexa:594–595). Kept separate from hx_is_wide_cjk so
// callers can distinguish "wide because SMP CJK" from "wide because
// emoji". Matches the hexa source's two back-to-back range checks.
int hx_is_smp_cjk(int cp) {
    if (cp >= 131072 && cp <= 196605) return 1;   // Ext-B..F
    if (cp >= 196608 && cp <= 262141) return 1;   // Ext-G
    return 0;
}
