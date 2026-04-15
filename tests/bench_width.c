// bench_width.c — micro-benchmark for hx_is_wide_cjk.
//
// Target (BUILD_SPEED_PLAN B2): < 3.3 ns/call so that 5M calls/frame
// at 60 Hz (300M/s) stays inside one frame with headroom.
//
// Workload mix (approximates real terminal stream w/ mixed content):
//   60% ASCII  (cp 0x20..0x7E)        — fast-path branch (cp < 4352)
//   30% CJK    (U+4E00..U+9FFF)       — BMP page table, tag==1
//   10% emoji  (U+1F300..U+1F9FF)     — non-BMP range scan
//
// Build:
//   clang -O2 -Wall tests/bench_width.c src/widths.c -o /tmp/bench_width
// Run:
//   /tmp/bench_width
//
// Also emits a self-check comparing a handful of known cp's against
// the expected width (so a silent table miscopy breaks the bench, not
// just the terminal).

#include "../src/widths.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

// ── cp stream generation ────────────────────────────────────────────
// Fixed seed + xorshift so numbers are reproducible across runs. We
// pre-materialize the stream into a heap array so the loop does only
// the width call (no RNG/mix branch leak into the bench).
static uint64_t xs_state = 0x9E3779B97F4A7C15ULL;
static inline uint32_t xs_next(void) {
    uint64_t x = xs_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    xs_state = x;
    return (uint32_t)x;
}

// class: 0=ASCII, 1=CJK, 2=emoji — class picked on 60/30/10 split.
static int pick_cp_in_class(int cls, uint32_t r) {
    if (cls == 0) return 0x20 + (int)(r % (0x7F - 0x20));
    if (cls == 1) return 0x4E00 + (int)(r % (0x9FFF - 0x4E00 + 1));
    return 0x1F300 + (int)(r % (0x1F9FF - 0x1F300 + 1));
}

static int pick_class_random(void) {
    uint32_t r = xs_next() % 100;
    if (r < 60) return 0;
    if (r < 90) return 1;
    return 2;
}

// Pure-random mix: each cp independently sampled — worst case for the
// branch predictor, so the ns/call number here is a pessimistic upper
// bound for real terminal traffic.
static int *gen_stream_random(size_t n) {
    int *buf = malloc(n * sizeof(int));
    if (!buf) { perror("malloc"); exit(1); }
    for (size_t i = 0; i < n; i++) {
        int cls = pick_class_random();
        buf[i] = pick_cp_in_class(cls, xs_next());
    }
    return buf;
}

// Clustered mix: 64-cp runs of the same class, preserving the 60/30/10
// overall ratio. Closer to real terminal content (paragraphs of ASCII
// punctuated by CJK runs, emoji clusters, etc.) — branch predictor
// locks into each run.
static int *gen_stream_clustered(size_t n) {
    int *buf = malloc(n * sizeof(int));
    if (!buf) { perror("malloc"); exit(1); }
    size_t i = 0;
    while (i < n) {
        int cls = pick_class_random();
        size_t run = 64;
        if (i + run > n) run = n - i;
        for (size_t j = 0; j < run; j++) {
            buf[i + j] = pick_cp_in_class(cls, xs_next());
        }
        i += run;
    }
    return buf;
}

// ── timing helper ───────────────────────────────────────────────────
static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

// ── self-check ──────────────────────────────────────────────────────
// A few anchors that MUST match hexa. If any fails the bench aborts.
struct anchor { int cp; int expected; const char *name; };
static const struct anchor anchors[] = {
    { 0x0041,     0, "'A'" },                    // ASCII narrow
    { 0x00E9,     0, "'e-acute'" },              // Latin-1 narrow
    { 0x1100,     1, "HANGUL CHOSEONG KIYEOK" }, // mixed page 17 → range hit
    { 0x4E00,     1, "CJK one" },                // page 78 wide
    { 0xAC00,     1, "HANGUL SYLLABLE GA" },     // page 172 wide
    { 0xFF21,     1, "FULLWIDTH A" },            // mixed page 255 → range hit
    { 0xFFEF,     0, "after mixed range" },      // mixed page 255 → fall through
    { 0x1F600,    1, "GRINNING FACE" },          // emoji block
    { 0x20000,    1, "CJK Ext-B start" },        // SMP Ext-B
    { 0x30000,    1, "CJK Ext-G start" },        // SMP Ext-G
    { 0xE0000,    0, "Tag block" },              // beyond wide ranges
};

static int run_self_check(void) {
    int failed = 0;
    for (size_t i = 0; i < sizeof(anchors)/sizeof(anchors[0]); i++) {
        int got = hx_is_wide_cjk(anchors[i].cp);
        if (got != anchors[i].expected) {
            fprintf(stderr, "self-check FAIL: %s (U+%04X) expected %d got %d\n",
                    anchors[i].name, anchors[i].cp, anchors[i].expected, got);
            failed++;
        }
    }
    // Quick sanity for helpers
    if (hx_is_emoji_modifier(0x1F3FB) != 1) { fprintf(stderr, "emoji_mod start fail\n"); failed++; }
    if (hx_is_emoji_modifier(0x1F3FF) != 1) { fprintf(stderr, "emoji_mod end fail\n"); failed++; }
    if (hx_is_emoji_modifier(0x1F3FA) != 0) { fprintf(stderr, "emoji_mod before fail\n"); failed++; }
    if (hx_is_zwj(0x200D)              != 1) { fprintf(stderr, "zwj fail\n"); failed++; }
    if (hx_is_vs16(0xFE0F)             != 1) { fprintf(stderr, "vs16 fail\n"); failed++; }
    if (hx_is_smp_cjk(0x20000)         != 1) { fprintf(stderr, "smp start fail\n"); failed++; }
    if (hx_is_smp_cjk(0x3FFFD)         != 1) { fprintf(stderr, "smp end fail\n"); failed++; }
    return failed;
}

// ── bench driver ────────────────────────────────────────────────────
static void bench_stream(int *stream, size_t n, const char *label) {
    // Warm-up pass (page-in + branch predictor) — result XOR'd into a
    // volatile sink so the compiler cannot elide it.
    volatile int sink = 0;
    for (size_t i = 0; i < n; i++) sink ^= hx_is_wide_cjk(stream[i]);

    double t0 = now_ns();
    int acc = 0;
    for (size_t i = 0; i < n; i++) acc += hx_is_wide_cjk(stream[i]);
    double t1 = now_ns();
    sink ^= acc;

    double elapsed_ns = t1 - t0;
    double ns_per_call = elapsed_ns / (double)n;
    double m_per_sec = 1e3 / ns_per_call;
    printf("  %-20s n=%9zu  total=%8.2f ms  ns/call=%6.3f  throughput=%7.1f M/s  (wide=%d)\n",
           label, n, elapsed_ns / 1e6, ns_per_call, m_per_sec, acc);
    (void)sink;
}

static void bench(size_t n, const char *size_label) {
    int *s1 = gen_stream_random(n);
    int *s2 = gen_stream_clustered(n);
    char buf[64];
    snprintf(buf, sizeof(buf), "%s random-mix",   size_label);
    bench_stream(s1, n, buf);
    snprintf(buf, sizeof(buf), "%s clustered-64", size_label);
    bench_stream(s2, n, buf);
    free(s1);
    free(s2);
}

int main(void) {
    if (run_self_check() != 0) {
        fprintf(stderr, "self-check failed — aborting bench\n");
        return 1;
    }
    puts("hx_is_wide_cjk micro-bench (mix: 60% ASCII / 30% CJK / 10% emoji)");
    puts("  random-mix:   each cp independently sampled (pessimistic — worst-case branch prediction)");
    puts("  clustered-64: 64-cp runs of the same class (realistic terminal traffic)");
    bench(   100000, "warmup");
    bench( 1000000,  "1M");
    bench(10000000,  "10M");
    puts("target: < 3.3 ns/call (= 300 M/s) per BUILD_SPEED_PLAN B2");
    return 0;
}
