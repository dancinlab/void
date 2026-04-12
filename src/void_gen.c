#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>

static const double PI = 3.14159265358979323846;
static const double E = 2.71828182845904523536;
static long hexa_time_unix(void) { return (long)time(NULL); }
static double hexa_clock(void) { return (double)clock() / CLOCKS_PER_SEC; }
static double hexa_sqrt(double x) { return sqrt(x); }
static double hexa_pow(double b, double e) { return pow(b, e); }
static double hexa_abs_f(double x) { return x < 0 ? -x : x; }
static long hexa_abs_i(long x) { return x < 0 ? -x : x; }
static double hexa_sin(double x) { return sin(x); }
static double hexa_cos(double x) { return cos(x); }
static double hexa_tan(double x) { return tan(x); }
static double hexa_log(double x) { return log(x); }
static double hexa_log10(double x) { return log10(x); }
static double hexa_exp(double x) { return exp(x); }
static double hexa_floor(double x) { return floor(x); }
static double hexa_ceil(double x) { return ceil(x); }
static double hexa_round(double x) { return (x >= 0) ? (long)(x + 0.5) : (long)(x - 0.5); }
// hexa_alloc: 단순 malloc wrapper (무제한)
static char* hexa_alloc(size_t n) {
    char* p = (char*)malloc(n);
    if (!p) { fprintf(stderr, "hexa_alloc oom (%zu)\n", n); exit(1); }
    return p;
}
static const char* hexa_concat(const char* a, const char* b) {
    size_t la = strlen(a), lb = strlen(b);
    char* p = hexa_alloc(la + lb + 1);
    memcpy(p, a, la); memcpy(p + la, b, lb); p[la + lb] = 0;
    return p;
}
static const char* hexa_timestamp(void) {
    time_t t = time(NULL); struct tm* lt = localtime(&t);
    char* p = hexa_alloc(32);
    strftime(p, 32, "%Y-%m-%d %H:%M:%S", lt);
    return p;
}
static const char* hexa_int_to_str(long v) {
    char* p = hexa_alloc(24);
    snprintf(p, 24, "%ld", v);
    return p;
}
static const char* hexa_float_to_str(double v) {
    char* p = hexa_alloc(32);
    snprintf(p, 32, "%g", v);
    return p;
}
static const char* hexa_substr(const char* s, long a, long b) {
    long sl = (long)strlen(s);
    if (a < 0) a = 0; if (b > sl) b = sl; if (a > b) a = b;
    long n = b - a;
    char* p = hexa_alloc(n + 1);
    memcpy(p, s + a, n); p[n] = 0;
    return p;
}
static long hexa_str_len(const char* s) { return (long)strlen(s); }
static long hexa_contains(const char* h, const char* n) { return strstr(h, n) ? 1 : 0; }
static long hexa_index_of(const char* h, const char* n) {
    const char* p = strstr(h, n); if (!p) return -1;
    return (long)(p - h);
}
static long hexa_starts_with(const char* h, const char* n) {
    size_t ln = strlen(n); return strncmp(h, n, ln) == 0 ? 1 : 0;
}
static long hexa_ends_with(const char* h, const char* n) {
    size_t lh = strlen(h), ln = strlen(n);
    if (ln > lh) return 0; return strcmp(h + lh - ln, n) == 0 ? 1 : 0;
}
static const char* hexa_trim(const char* s) {
    while (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r') s++;
    long n = (long)strlen(s);
    while (n > 0 && (s[n-1]==' '||s[n-1]=='\t'||s[n-1]=='\n'||s[n-1]=='\r')) n--;
    char* p = hexa_alloc(n + 1);
    memcpy(p, s, n); p[n] = 0;
    return p;
}
static const char* hexa_to_upper(const char* s) {
    long n = (long)strlen(s); char* p = hexa_alloc(n + 1);
    for (long i = 0; i < n; i++) { char c = s[i]; p[i] = (c>='a'&&c<='z') ? c - 32 : c; }
    p[n] = 0; return p;
}
static const char* hexa_to_lower(const char* s) {
    long n = (long)strlen(s); char* p = hexa_alloc(n + 1);
    for (long i = 0; i < n; i++) { char c = s[i]; p[i] = (c>='A'&&c<='Z') ? c + 32 : c; }
    p[n] = 0; return p;
}
static long hexa_parse_int(const char* s) {
    while (*s == ' ' || *s == '\t') s++;
    long sign = 1; if (*s == '-') { sign = -1; s++; } else if (*s == '+') s++;
    long v = 0; while (*s >= '0' && *s <= '9') { v = v*10 + (*s - '0'); s++; }
    return sign * v;
}
#include <stdlib.h>
static double hexa_to_float(const char* s) { return strtod(s, NULL); }
static long* hexa_struct_alloc(const long* items, long n) {
    long* p = (long*)hexa_alloc(n * sizeof(long));
    memcpy(p, items, n * sizeof(long));
    return p;
}
static const char* hexa_env(const char* name) {
    const char* v = getenv(name); return v ? v : "";
}
static const char* hexa_replace(const char* s, const char* old_, const char* new_) {
    long oln = (long)strlen(old_); if (oln == 0) return s;
    long sl = (long)strlen(s), nl = (long)strlen(new_);
    // 결과 최대 길이 = s 길이 * (new/old 비율)
    long cap = sl + 1; if (nl > oln) cap = sl * (nl / oln + 1) + 1;
    char* out = hexa_alloc(cap + 64);
    long oi = 0; const char* cur = s;
    while (*cur) {
        if (strncmp(cur, old_, oln) == 0) {
            memcpy(out + oi, new_, nl); oi += nl; cur += oln;
        } else { out[oi++] = *cur++; }
    }
    out[oi] = 0; return out;
}
static const char* hexa_read_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return "";
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    char* p = hexa_alloc(sz + 1);
    fread(p, 1, sz, f); p[sz] = 0; fclose(f);
    return p;
}
static long hexa_write_file(const char* path, const char* content) {
    FILE* f = fopen(path, "wb");
    if (!f) return 0;
    size_t n = strlen(content);
    fwrite(content, 1, n, f); fclose(f);
    return (long)n;
}
static long hexa_file_exists(const char* path) {
    FILE* f = fopen(path, "rb"); if (!f) return 0; fclose(f); return 1;
}
static long hexa_dir_exists(const char* path) {
    struct stat st; if (stat(path, &st) != 0) return 0; return S_ISDIR(st.st_mode) ? 1 : 0;
}
static long hexa_mkdir(const char* path) {
    char tmp[1024]; snprintf(tmp, sizeof(tmp), "%s", path);
    for (char* p = tmp + 1; *p; p++) { if (*p == '/') { *p = 0; mkdir(tmp, 0755); *p = '/'; } }
    return (mkdir(tmp, 0755) == 0 || errno == EEXIST) ? 0 : 1;
}
typedef struct { long* d; long n; long cap; } hexa_arr;
#define _HA(a) ((hexa_arr*)(a))
#define _AD(a) (_HA(a)->d)
#define _AN(a) (_HA(a)->n)
static long hexa_arr_new(void) {
    hexa_arr* p = (hexa_arr*)malloc(sizeof(hexa_arr));
    p->d = NULL; p->n = 0; p->cap = 0; return (long)p;
}
static long hexa_arr_lit(const long* items, long n) {
    hexa_arr* p = (hexa_arr*)malloc(sizeof(hexa_arr));
    p->d = (long*)malloc((n>0?n:1)*sizeof(long)); p->n = n; p->cap = (n>0?n:1);
    if (n > 0) memcpy(p->d, items, n*sizeof(long));
    return (long)p;
}
static long hexa_arr_push(long a, long x) {
    hexa_arr* p = _HA(a);
    if (p->n >= p->cap) {
        p->cap = p->cap ? p->cap * 2 : 4;
        p->d = (long*)realloc(p->d, p->cap * sizeof(long));
    }
    p->d[p->n++] = x;
    return a;
}
static long hexa_arr_len(long a) { return a ? _AN(a) : 0; }
static long hexa_arr_get(long a, long i) { return _AD(a)[i]; }
static long hexa_arr_fill(long n, long v) {
    hexa_arr* p = (hexa_arr*)malloc(sizeof(hexa_arr));
    p->n = n; p->cap = n > 0 ? n : 1;
    p->d = (long*)malloc(p->cap * sizeof(long));
    for (long i = 0; i < n; i++) p->d[i] = v;
    return (long)p;
}
static long hexa_arr_concat(long a, long b) {
    long an = a ? _AN(a) : 0, bn = b ? _AN(b) : 0;
    hexa_arr* p = (hexa_arr*)malloc(sizeof(hexa_arr));
    p->n = an + bn; p->cap = p->n > 0 ? p->n : 1;
    p->d = (long*)malloc(p->cap * sizeof(long));
    if (an > 0) memcpy(p->d, _AD(a), an * sizeof(long));
    if (bn > 0) memcpy(p->d + an, _AD(b), bn * sizeof(long));
    return (long)p;
}
static long hexa_list_dir(const char* path) {
    long a = hexa_arr_new();
    DIR* d = opendir(path); if (!d) return a;
    struct dirent* e; while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.' && (e->d_name[1] == 0 || (e->d_name[1] == '.' && e->d_name[2] == 0))) continue;
        char* s = hexa_alloc(strlen(e->d_name) + 1); strcpy(s, e->d_name);
        a = hexa_arr_push(a, (long)s);
    }
    closedir(d); return a;
}
static long hexa_to_int_str(const char* s) { return strtol(s, NULL, 10); }
static long hexa_append_file(const char* path, const char* content) {
    FILE* f = fopen(path, "ab");
    if (!f) return 0;
    size_t n = strlen(content);
    fwrite(content, 1, n, f); fclose(f);
    return (long)n;
}
static const char* hexa_read_stdin(void) {
    char buf[8192]; size_t total = 0;
    char* out = hexa_alloc(65536);
    size_t r; while ((r = fread(buf, 1, sizeof(buf), stdin)) > 0) {
        if (total + r >= 65535) break;
        memcpy(out + total, buf, r); total += r;
    }
    out[total] = 0; return out;
}
static const char* hexa_exec_with_status(const char* cmd) {
    FILE* f = popen(cmd, "r");
    if (!f) return "-1|";
    char buf[8192]; size_t total = 0;
    char* out = hexa_alloc(16384);
    size_t rd; while ((rd = fread(buf, 1, sizeof(buf), f)) > 0) {
        if (total + rd >= 16000) break;
        memcpy(out + total, buf, rd); total += rd;
    }
    out[total] = 0; int rc = pclose(f);
    while (total > 0 && (out[total-1] == '\n' || out[total-1] == '\r')) { out[--total] = 0; }
    char* formatted = hexa_alloc(total + 32);
    snprintf(formatted, total + 32, "%d|%s", WEXITSTATUS(rc), out);
    return formatted;
}
static const char* hexa_exec(const char* cmd) {
    FILE* f = popen(cmd, "r");
    if (!f) return "";
    char buf[8192]; size_t total = 0;
    char* out = hexa_alloc(8192);
    size_t r; while ((r = fread(buf, 1, sizeof(buf), f)) > 0) {
        if (total + r >= 8191) break;
        memcpy(out + total, buf, r); total += r;
    }
    out[total] = 0; pclose(f);
    while (total > 0 && (out[total-1] == '\n' || out[total-1] == '\r')) { out[--total] = 0; }
    return out;
}
static long hexa_chars(const char* s) {
    long n = (long)strlen(s);
    long a = hexa_arr_new();
    for (long i = 0; i < n; i++) a = hexa_arr_push(a, (long)(unsigned char)s[i]);
    return a;
}
#include <ctype.h>
static long hexa_is_alpha(long c) { return (long)(isalpha((int)c) ? 1 : 0); }
static long hexa_is_alnum(long c) { return (long)(isalnum((int)c) ? 1 : 0); }
static int hexa_main_argc = 0;
static char** hexa_main_argv = NULL;
static long hexa_args(void) {
    long a = hexa_arr_new();
    for (int i = 0; i < hexa_main_argc; i++) a = hexa_arr_push(a, (long)hexa_main_argv[i]);
    return a;
}
static const char* hexa_arg(long i) {
    if (i < 0 || i >= hexa_main_argc) return "";
    return hexa_main_argv[i];
}
static long hexa_argc(void) { return (long)hexa_main_argc; }
static long hexa_split(const char* s, const char* sep) {
    long a = hexa_arr_new();
    long sl = (long)strlen(sep); if (sl == 0) { return hexa_arr_push(a, (long)s); }
    const char* cur = s;
    while (1) {
        const char* hit = strstr(cur, sep);
        if (!hit) {
            long ln = (long)strlen(cur);
            char* p = hexa_alloc(ln + 1);
            memcpy(p, cur, ln); p[ln] = 0;
            a = hexa_arr_push(a, (long)p);
            break;
        }
        long ln = hit - cur;
        char* p = hexa_alloc(ln + 1);
        memcpy(p, cur, ln); p[ln] = 0;
        a = hexa_arr_push(a, (long)p);
        cur = hit + sl;
    }
    return a;
}

long scr_mark_dirty(long r);
long scr_mark_all_dirty();
long scr_init();
long alt_save_from_scr();
long alt_restore_to_scr();
long scr_clear_all();
long enter_alt_screen(long do_save, long do_clear);
long leave_alt_screen(long do_restore);
long scr_scroll_up();
long scr_scroll_down();
long vt_csi_reset();
long vt_csi_flush();
long vt_csi_get(long idx, long def);
long sgr_apply();
long is_wide_cjk_mixed(long cp);
long is_wide_cjk(long cp);
long hangul_flush_pending();
long scr_put(long cp);
long scr_put_raw(long cp);
long csi_dispatch(long b);
long scr_feed_byte(long b);
long sync_to_bridge();
long scr_find_probe(long probe, long probe_len);
long self_test();
long load_from_bridge();
long vt_reset_state();
long hexa_user_main();

static long COLS = 80;
static long ROWS = 24;
static long TOTAL = 1920;
static long scr_cells;
static long scr_fg;
static long scr_bg;
static long scr_flags;
static long scr_dirty;
static long scr_all_dirty = 1;
static long scr_cur_x = 0;
static long scr_cur_y = 0;
static long scr_scroll_top = 0;
static long scr_scroll_bot = 23;
static long alt_cells;
static long alt_fg;
static long alt_bg;
static long alt_flags;
static long alt_cur_x = 0;
static long alt_cur_y = 0;
static long alt_saved_cur_x = 0;
static long alt_saved_cur_y = 0;
static long alt_saved_fg = 7;
static long alt_saved_bg = 0;
static long alt_saved_bold = 0;
static long alt_saved_underline = 0;
static long alt_saved_inverse = 0;
static long scr_is_alt = 0;
static long alt_buf_len = 0;
static long vt_state = 0;
static long vt_param = 0;
static long vt_params;
static long vt_param_started = 0;
static long vt_private = 0;
static long cur_fg = 7;
static long cur_bg = 0;
static long cur_bold = 0;
static long cur_underline = 0;
static long cur_inverse = 0;
static long osc_num = 0;
static long osc_title_bytes;
static long saved_cur_x = 0;
static long saved_cur_y = 0;
static long utf8_cp = 0;
static long utf8_remain = 0;
static long vt_ground;
static long vt_utf8_base;
static long vt_utf8_remain;
static long cur_charset = 0;
static long wide_pages;
static long g_hangul_L;
static long g_hangul_V;

extern int hexa_pty_spawn_login_shell(void);
extern int hexa_pty_poll_read(int fd, int timeout_ms);
extern int hexa_pty_read_byte(int idx);
extern int hexa_sh_reap(void);
extern int hexa_sh_spawn(void);
extern int hexa_sh_reset_accum(void);
extern int hexa_sh_write_canned(int fd, int idx);
extern int hexa_term_drain_master(int master, int timeout_ms);
extern int hexa_sh_accum_len_q(void);
extern int hexa_sh_accum_byte_at(int idx);
extern int hexa_sleep_us(int us);
extern int hexa_check_test_mode(void);
extern int hexa_appkit_init_term(int rows, int cols, int font_size);
extern void hexa_appkit_term_set_cell(int row, int col, int ch, int fg, int bg, int flags);
extern void hexa_appkit_term_set_cursor(int row, int col, int vis);
extern void hexa_appkit_term_flush(void);
extern int hexa_appkit_term_poll(void);
extern int hexa_keys_to_pty(int master_fd);
extern int hexa_tab_new(void);
extern int hexa_tab_close(int idx);
extern int hexa_tab_get_pty(void);
extern int hexa_tab_nudge_pty(void);
extern int hexa_tab_poll_cmd(void);
extern int hexa_tab_count(void);
extern int hexa_tab_get_active(void);
extern int hexa_tab_cell_cp(int idx);
extern int hexa_tab_cell_fg(int idx);
extern int hexa_tab_cell_bg(int idx);
extern int hexa_tab_cell_flags(int idx);
extern int hexa_tab_cursor_x(void);
extern int hexa_tab_cursor_y(void);
extern int hexa_appkit_term_check_resize(void);
extern int hexa_appkit_term_get_rows(void);
extern int hexa_appkit_term_get_cols(void);
extern int hexa_pty_resize(int fd, int rows, int cols);
extern void hexa_appkit_term_title_reset(void);
extern void hexa_appkit_term_title_push(int b);
extern void hexa_appkit_term_title_apply(void);
extern void hexa_appkit_cwd_reset(void);
extern void hexa_appkit_cwd_push(int b);
extern void hexa_appkit_cwd_apply(void);
extern int hexa_scrollback_push_begin(void);
extern int hexa_scrollback_push_cell(int ch, int fg, int bg, int flags);
extern int hexa_scrollback_push_end(void);
extern int hexa_reply_reset(void);
extern int hexa_reply_push(int b);
extern int hexa_reply_flush(void);
extern int hexa_keybuf_len(void);
extern int hexa_keybuf_byte(int idx);
extern int hexa_keybuf_clear(void);
extern int clock_us(void);

long scr_mark_dirty(long r) {
    if (((r >= 0) && (r < ROWS))) {
        _AD(scr_dirty)[r] = 1;
    }
    return 0;
}

long scr_mark_all_dirty() {
    long r = 0;
    while ((r < ROWS)) {
        _AD(scr_dirty)[r] = 1;
        r = (r + 1);
    }
    scr_all_dirty = 1;
    return 0;
}

long scr_init() {
    scr_cells = hexa_arr_new();
    scr_fg = hexa_arr_new();
    scr_bg = hexa_arr_new();
    scr_flags = hexa_arr_new();
    scr_dirty = hexa_arr_new();
    long i = 0;
    while ((i < TOTAL)) {
        scr_cells = hexa_arr_push(scr_cells, 32);
        scr_fg = hexa_arr_push(scr_fg, 7);
        scr_bg = hexa_arr_push(scr_bg, 0);
        scr_flags = hexa_arr_push(scr_flags, 0);
        i = (i + 1);
    }
    long r = 0;
    while ((r < 200)) {
        scr_dirty = hexa_arr_push(scr_dirty, 1);
        r = (r + 1);
    }
    scr_all_dirty = 1;
    scr_cur_x = 0;
    scr_cur_y = 0;
    scr_scroll_top = 0;
    scr_scroll_bot = (ROWS - 1);
    alt_cells = hexa_arr_new();
    alt_fg = hexa_arr_new();
    alt_bg = hexa_arr_new();
    alt_flags = hexa_arr_new();
    long ai = 0;
    while ((ai < TOTAL)) {
        alt_cells = hexa_arr_push(alt_cells, 32);
        alt_fg = hexa_arr_push(alt_fg, 7);
        alt_bg = hexa_arr_push(alt_bg, 0);
        alt_flags = hexa_arr_push(alt_flags, 0);
        ai = (ai + 1);
    }
    alt_buf_len = TOTAL;
    alt_cur_x = 0;
    alt_cur_y = 0;
    alt_saved_cur_x = 0;
    alt_saved_cur_y = 0;
    alt_saved_fg = 7;
    alt_saved_bg = 0;
    alt_saved_bold = 0;
    alt_saved_underline = 0;
    alt_saved_inverse = 0;
    scr_is_alt = 0;
    return 0;
}

long alt_save_from_scr() {
    long i = 0;
    while ((i < TOTAL)) {
        _AD(alt_cells)[i] = _AD(scr_cells)[i];
        _AD(alt_fg)[i] = _AD(scr_fg)[i];
        _AD(alt_bg)[i] = _AD(scr_bg)[i];
        _AD(alt_flags)[i] = _AD(scr_flags)[i];
        i = (i + 1);
    }
    alt_cur_x = scr_cur_x;
    alt_cur_y = scr_cur_y;
    return 0;
}

long alt_restore_to_scr() {
    long i = 0;
    while ((i < TOTAL)) {
        _AD(scr_cells)[i] = _AD(alt_cells)[i];
        _AD(scr_fg)[i] = _AD(alt_fg)[i];
        _AD(scr_bg)[i] = _AD(alt_bg)[i];
        _AD(scr_flags)[i] = _AD(alt_flags)[i];
        i = (i + 1);
    }
    scr_cur_x = alt_cur_x;
    scr_cur_y = alt_cur_y;
    return 0;
}

long scr_clear_all() {
    long i = 0;
    while ((i < TOTAL)) {
        _AD(scr_cells)[i] = 32;
        _AD(scr_fg)[i] = 7;
        _AD(scr_bg)[i] = 0;
        _AD(scr_flags)[i] = 0;
        i = (i + 1);
    }
    (void)(scr_mark_all_dirty());
    scr_cur_x = 0;
    scr_cur_y = 0;
    return 0;
}

long enter_alt_screen(long do_save, long do_clear) {
    if ((scr_is_alt == 1)) {
        return 0;
    }
    if ((do_save == 1)) {
        alt_saved_cur_x = scr_cur_x;
        alt_saved_cur_y = scr_cur_y;
        alt_saved_fg = cur_fg;
        alt_saved_bg = cur_bg;
        alt_saved_bold = cur_bold;
        alt_saved_underline = cur_underline;
        alt_saved_inverse = cur_inverse;
    }
    (void)(alt_save_from_scr());
    if ((do_clear == 1)) {
        (void)(scr_clear_all());
    } else {
        scr_cur_x = 0;
        scr_cur_y = 0;
    }
    scr_is_alt = 1;
    return 0;
}

long leave_alt_screen(long do_restore) {
    if ((scr_is_alt == 0)) {
        return 0;
    }
    (void)(alt_restore_to_scr());
    if ((do_restore == 1)) {
        scr_cur_x = alt_saved_cur_x;
        scr_cur_y = alt_saved_cur_y;
        cur_fg = alt_saved_fg;
        cur_bg = alt_saved_bg;
        cur_bold = alt_saved_bold;
        cur_underline = alt_saved_underline;
        cur_inverse = alt_saved_inverse;
    }
    scr_is_alt = 0;
    return 0;
}

long scr_scroll_up() {
    if ((scr_scroll_top == 0)) {
        (void)(hexa_scrollback_push_begin());
        long sc = 0;
        while ((sc < COLS)) {
            (void)(hexa_scrollback_push_cell(_AD(scr_cells)[sc], _AD(scr_fg)[sc], _AD(scr_bg)[sc], _AD(scr_flags)[sc]));
            sc = (sc + 1);
        }
        (void)(hexa_scrollback_push_end());
    }
    long dr = scr_scroll_top;
    while ((dr <= scr_scroll_bot)) {
        (void)(scr_mark_dirty(dr));
        dr = (dr + 1);
    }
    long r = scr_scroll_top;
    while ((r < scr_scroll_bot)) {
        long dst = (r * COLS);
        long src = ((r + 1) * COLS);
        long c = 0;
        while ((c < COLS)) {
            _AD(scr_cells)[(dst + c)] = _AD(scr_cells)[(src + c)];
            _AD(scr_fg)[(dst + c)] = _AD(scr_fg)[(src + c)];
            _AD(scr_bg)[(dst + c)] = _AD(scr_bg)[(src + c)];
            _AD(scr_flags)[(dst + c)] = _AD(scr_flags)[(src + c)];
            c = (c + 1);
        }
        r = (r + 1);
    }
    long bot = (scr_scroll_bot * COLS);
    long c = 0;
    while ((c < COLS)) {
        _AD(scr_cells)[(bot + c)] = 32;
        _AD(scr_fg)[(bot + c)] = 7;
        _AD(scr_bg)[(bot + c)] = 0;
        _AD(scr_flags)[(bot + c)] = 0;
        c = (c + 1);
    }
    return 0;
}

long scr_scroll_down() {
    long dr = scr_scroll_top;
    while ((dr <= scr_scroll_bot)) {
        (void)(scr_mark_dirty(dr));
        dr = (dr + 1);
    }
    long r = scr_scroll_bot;
    while ((r > scr_scroll_top)) {
        long dst = (r * COLS);
        long src = ((r - 1) * COLS);
        long c = 0;
        while ((c < COLS)) {
            _AD(scr_cells)[(dst + c)] = _AD(scr_cells)[(src + c)];
            _AD(scr_fg)[(dst + c)] = _AD(scr_fg)[(src + c)];
            _AD(scr_bg)[(dst + c)] = _AD(scr_bg)[(src + c)];
            _AD(scr_flags)[(dst + c)] = _AD(scr_flags)[(src + c)];
            c = (c + 1);
        }
        r = (r - 1);
    }
    long top = (scr_scroll_top * COLS);
    long c = 0;
    while ((c < COLS)) {
        _AD(scr_cells)[(top + c)] = 32;
        _AD(scr_fg)[(top + c)] = 7;
        _AD(scr_bg)[(top + c)] = 0;
        _AD(scr_flags)[(top + c)] = 0;
        c = (c + 1);
    }
    return 0;
}

long vt_csi_reset() {
    vt_params = hexa_arr_new();
    vt_param = 0;
    vt_param_started = 0;
    vt_private = 0;
    return 0;
}

long vt_csi_flush() {
    if ((vt_param_started == 1)) {
        vt_params = hexa_arr_push(vt_params, vt_param);
    }
    vt_param = 0;
    vt_param_started = 0;
    return 0;
}

long vt_csi_get(long idx, long def) {
    if ((idx < _AN(vt_params))) {
        return _AD(vt_params)[idx];
    }
    return def;
}

long sgr_apply() {
    long n = _AN(vt_params);
    if ((n == 0)) {
        cur_fg = 7;
        cur_bg = 0;
        cur_bold = 0;
        cur_underline = 0;
        cur_inverse = 0;
        return 0;
    }
    long i = 0;
    while ((i < n)) {
        long c = _AD(vt_params)[i];
        if ((c == 0)) {
            cur_fg = 7;
            cur_bg = 0;
            cur_bold = 0;
            cur_underline = 0;
            cur_inverse = 0;
        } else {
            if ((c == 1)) {
                cur_bold = 1;
            } else {
                if ((c == 4)) {
                    cur_underline = 1;
                } else {
                    if ((c == 7)) {
                        cur_inverse = 1;
                    } else {
                        if ((c == 22)) {
                            cur_bold = 0;
                        } else {
                            if ((c == 24)) {
                                cur_underline = 0;
                            } else {
                                if ((c == 27)) {
                                    cur_inverse = 0;
                                } else {
                                    if ((c == 39)) {
                                        cur_fg = 7;
                                    } else {
                                        if ((c == 49)) {
                                            cur_bg = 0;
                                        } else {
                                            if ((c == 38)) {
                                                if (((i + 2) < n)) {
                                                    if ((_AD(vt_params)[(i + 1)] == 5)) {
                                                        cur_fg = _AD(vt_params)[(i + 2)];
                                                        i = (i + 2);
                                                    } else {
                                                        if ((_AD(vt_params)[(i + 1)] == 2)) {
                                                            if (((i + 4) < n)) {
                                                                long r = _AD(vt_params)[(i + 2)];
                                                                long g = _AD(vt_params)[(i + 3)];
                                                                long b = _AD(vt_params)[(i + 4)];
                                                                cur_fg = (((256 + (r * 65536)) + (g * 256)) + b);
                                                                i = (i + 4);
                                                            }
                                                        }
                                                    }
                                                }
                                            } else {
                                                if ((c == 48)) {
                                                    if (((i + 2) < n)) {
                                                        if ((_AD(vt_params)[(i + 1)] == 5)) {
                                                            cur_bg = _AD(vt_params)[(i + 2)];
                                                            i = (i + 2);
                                                        } else {
                                                            if ((_AD(vt_params)[(i + 1)] == 2)) {
                                                                if (((i + 4) < n)) {
                                                                    long r = _AD(vt_params)[(i + 2)];
                                                                    long g = _AD(vt_params)[(i + 3)];
                                                                    long b = _AD(vt_params)[(i + 4)];
                                                                    cur_bg = (((256 + (r * 65536)) + (g * 256)) + b);
                                                                    i = (i + 4);
                                                                }
                                                            }
                                                        }
                                                    }
                                                } else {
                                                    if ((c >= 30)) {
                                                        if ((c <= 37)) {
                                                            cur_fg = (c - 30);
                                                        } else {
                                                            if ((c >= 40)) {
                                                                if ((c <= 47)) {
                                                                    cur_bg = (c - 40);
                                                                } else {
                                                                    if ((c >= 90)) {
                                                                        if ((c <= 97)) {
                                                                            cur_fg = ((c - 90) + 8);
                                                                        } else {
                                                                            if ((c >= 100)) {
                                                                                if ((c <= 107)) {
                                                                                    cur_bg = ((c - 100) + 8);
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        i = (i + 1);
    }
    return 0;
}

long is_wide_cjk_mixed(long cp) {
    if (((cp >= 4352) && (cp <= 4447))) {
        return 1;
    }
    if (((cp >= 11904) && (cp <= 12031))) {
        return 1;
    }
    if (((cp >= 12288) && (cp <= 12350))) {
        return 1;
    }
    if (((cp >= 12353) && (cp <= 12543))) {
        return 1;
    }
    if (((cp >= 19712) && (cp <= 19903))) {
        return 1;
    }
    if (((cp >= 41984) && (cp <= 42191))) {
        return 1;
    }
    if (((cp >= 55040) && (cp <= 55203))) {
        return 1;
    }
    if (((cp >= 65072) && (cp <= 65103))) {
        return 1;
    }
    if (((cp >= 65280) && (cp <= 65376))) {
        return 1;
    }
    if (((cp >= 65504) && (cp <= 65510))) {
        return 1;
    }
    return 0;
}

long is_wide_cjk(long cp) {
    if ((cp < 4352)) {
        return 0;
    }
    if (((cp >= 131072) && (cp <= 196605))) {
        return 1;
    }
    if (((cp >= 196608) && (cp <= 262141))) {
        return 1;
    }
    if ((cp > 65535)) {
        return 0;
    }
    long page = (cp / 256);
    long tag = _AD(wide_pages)[page];
    if ((tag == 0)) {
        return 0;
    }
    if ((tag == 1)) {
        return 1;
    }
    return is_wide_cjk_mixed(cp);
}

long hangul_flush_pending() {
    if (((g_hangul_L >= 0) && (g_hangul_V >= 0))) {
        long syl = ((44032 + (g_hangul_L * 588)) + (g_hangul_V * 28));
        g_hangul_L = (-1);
        g_hangul_V = (-1);
        (void)(scr_put_raw(syl));
        return 0;
    }
    if ((g_hangul_L >= 0)) {
        long lone = (4352 + g_hangul_L);
        g_hangul_L = (-1);
        (void)(scr_put_raw(lone));
    }
    return 0;
}

long scr_put(long cp) {
    if (((cp >= 4352) && (cp <= 4370))) {
        (void)(hangul_flush_pending());
        g_hangul_L = (cp - 4352);
        return 0;
    }
    if (((((cp >= 4449) && (cp <= 4469)) && (g_hangul_L >= 0)) && (g_hangul_V < 0))) {
        g_hangul_V = (cp - 4449);
        return 0;
    }
    if (((((cp >= 4520) && (cp <= 4546)) && (g_hangul_L >= 0)) && (g_hangul_V >= 0))) {
        long t_idx = (cp - 4519);
        long syl = (((44032 + (g_hangul_L * 588)) + (g_hangul_V * 28)) + t_idx);
        g_hangul_L = (-1);
        g_hangul_V = (-1);
        return scr_put_raw(syl);
    }
    (void)(hangul_flush_pending());
    return scr_put_raw(cp);
}

long scr_put_raw(long cp) {
    long wide = is_wide_cjk(cp);
    long advance = (((wide == 1)) ? (2) : (1));
    if (((scr_cur_x + advance) > COLS)) {
        scr_cur_x = 0;
        scr_cur_y = (scr_cur_y + 1);
        if ((scr_cur_y > scr_scroll_bot)) {
            (void)(scr_scroll_up());
            scr_cur_y = scr_scroll_bot;
        }
    }
    if ((scr_cur_y >= 0)) {
        if ((scr_cur_y < ROWS)) {
            (void)(scr_mark_dirty(scr_cur_y));
            long idx = ((scr_cur_y * COLS) + scr_cur_x);
            _AD(scr_cells)[idx] = cp;
            _AD(scr_fg)[idx] = cur_fg;
            _AD(scr_bg)[idx] = cur_bg;
            long f = 0;
            if ((cur_bold == 1)) {
                f = (f + 1);
            }
            if ((cur_underline == 1)) {
                f = (f + 4);
            }
            if ((cur_inverse == 1)) {
                f = (f + 8);
            }
            if ((wide == 1)) {
                f = (f + 65536);
            }
            _AD(scr_flags)[idx] = f;
            if (((wide == 1) && ((scr_cur_x + 1) < COLS))) {
                long idx2 = (idx + 1);
                _AD(scr_cells)[idx2] = 0;
                _AD(scr_fg)[idx2] = cur_fg;
                _AD(scr_bg)[idx2] = cur_bg;
                _AD(scr_flags)[idx2] = 131072;
            }
        }
    }
    scr_cur_x = (scr_cur_x + advance);
    return 0;
}

long csi_dispatch(long b) {
    (void)(vt_csi_flush());
    long vt_n = _AN(vt_params);
    if ((b == 72)) {
        long row = ((((vt_n > 0)) ? (_AD(vt_params)[0]) : (1)) - 1);
        long col = ((((vt_n > 1)) ? (_AD(vt_params)[1]) : (1)) - 1);
        if ((row < 0)) {
            row = 0;
        }
        if ((col < 0)) {
            col = 0;
        }
        if ((row >= ROWS)) {
            row = (ROWS - 1);
        }
        if ((col >= COLS)) {
            col = (COLS - 1);
        }
        scr_cur_y = row;
        scr_cur_x = col;
    } else {
        if ((b == 102)) {
            long row = ((((vt_n > 0)) ? (_AD(vt_params)[0]) : (1)) - 1);
            long col = ((((vt_n > 1)) ? (_AD(vt_params)[1]) : (1)) - 1);
            if ((row < 0)) {
                row = 0;
            }
            if ((col < 0)) {
                col = 0;
            }
            if ((row >= ROWS)) {
                row = (ROWS - 1);
            }
            if ((col >= COLS)) {
                col = (COLS - 1);
            }
            scr_cur_y = row;
            scr_cur_x = col;
        } else {
            if ((b == 65)) {
                long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                scr_cur_y = (scr_cur_y - n);
                if ((scr_cur_y < scr_scroll_top)) {
                    scr_cur_y = scr_scroll_top;
                }
            } else {
                if ((b == 66)) {
                    long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                    scr_cur_y = (scr_cur_y + n);
                    if ((scr_cur_y > scr_scroll_bot)) {
                        scr_cur_y = scr_scroll_bot;
                    }
                } else {
                    if ((b == 67)) {
                        long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                        scr_cur_x = (scr_cur_x + n);
                        if ((scr_cur_x >= COLS)) {
                            scr_cur_x = (COLS - 1);
                        }
                    } else {
                        if ((b == 68)) {
                            long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                            scr_cur_x = (scr_cur_x - n);
                            if ((scr_cur_x < 0)) {
                                scr_cur_x = 0;
                            }
                        } else {
                            if ((b == 74)) {
                                long mode = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (0));
                                if ((mode == 0)) {
                                    long dr = scr_cur_y;
                                    while ((dr < ROWS)) {
                                        (void)(scr_mark_dirty(dr));
                                        dr = (dr + 1);
                                    }
                                    long start = ((scr_cur_y * COLS) + scr_cur_x);
                                    long i = start;
                                    while ((i < TOTAL)) {
                                        _AD(scr_cells)[i] = 32;
                                        _AD(scr_fg)[i] = 7;
                                        _AD(scr_bg)[i] = 0;
                                        _AD(scr_flags)[i] = 0;
                                        i = (i + 1);
                                    }
                                } else {
                                    if ((mode == 1)) {
                                        long dr = 0;
                                        while ((dr <= scr_cur_y)) {
                                            (void)(scr_mark_dirty(dr));
                                            dr = (dr + 1);
                                        }
                                        long stop = ((scr_cur_y * COLS) + scr_cur_x);
                                        long i = 0;
                                        while ((i <= stop)) {
                                            _AD(scr_cells)[i] = 32;
                                            _AD(scr_fg)[i] = 7;
                                            _AD(scr_bg)[i] = 0;
                                            _AD(scr_flags)[i] = 0;
                                            i = (i + 1);
                                        }
                                    } else {
                                        if ((mode == 2)) {
                                            (void)(scr_mark_all_dirty());
                                            long i = 0;
                                            while ((i < TOTAL)) {
                                                _AD(scr_cells)[i] = 32;
                                                _AD(scr_fg)[i] = 7;
                                                _AD(scr_bg)[i] = 0;
                                                _AD(scr_flags)[i] = 0;
                                                i = (i + 1);
                                            }
                                        }
                                    }
                                }
                            } else {
                                if ((b == 75)) {
                                    (void)(scr_mark_dirty(scr_cur_y));
                                    long mode = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (0));
                                    long row_s = (scr_cur_y * COLS);
                                    if ((mode == 0)) {
                                        long i = (row_s + scr_cur_x);
                                        long row_e = (row_s + COLS);
                                        while ((i < row_e)) {
                                            _AD(scr_cells)[i] = 32;
                                            _AD(scr_fg)[i] = 7;
                                            _AD(scr_bg)[i] = 0;
                                            _AD(scr_flags)[i] = 0;
                                            i = (i + 1);
                                        }
                                    } else {
                                        if ((mode == 1)) {
                                            long i = row_s;
                                            long stop = (row_s + scr_cur_x);
                                            while ((i <= stop)) {
                                                _AD(scr_cells)[i] = 32;
                                                _AD(scr_fg)[i] = 7;
                                                _AD(scr_bg)[i] = 0;
                                                _AD(scr_flags)[i] = 0;
                                                i = (i + 1);
                                            }
                                        } else {
                                            if ((mode == 2)) {
                                                long i = row_s;
                                                long row_e = (row_s + COLS);
                                                while ((i < row_e)) {
                                                    _AD(scr_cells)[i] = 32;
                                                    _AD(scr_fg)[i] = 7;
                                                    _AD(scr_bg)[i] = 0;
                                                    _AD(scr_flags)[i] = 0;
                                                    i = (i + 1);
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    if ((b == 109)) {
                                        (void)(sgr_apply());
                                    } else {
                                        if ((b == 71)) {
                                            long col = ((((vt_n > 0)) ? (_AD(vt_params)[0]) : (1)) - 1);
                                            if ((col < 0)) {
                                                col = 0;
                                            }
                                            if ((col >= COLS)) {
                                                col = (COLS - 1);
                                            }
                                            scr_cur_x = col;
                                        } else {
                                            if ((b == 100)) {
                                                long row = ((((vt_n > 0)) ? (_AD(vt_params)[0]) : (1)) - 1);
                                                if ((row < 0)) {
                                                    row = 0;
                                                }
                                                if ((row >= ROWS)) {
                                                    row = (ROWS - 1);
                                                }
                                                scr_cur_y = row;
                                            } else {
                                                if ((b == 76)) {
                                                    long dr = scr_cur_y;
                                                    while ((dr <= scr_scroll_bot)) {
                                                        (void)(scr_mark_dirty(dr));
                                                        dr = (dr + 1);
                                                    }
                                                    long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                                                    long j = 0;
                                                    while ((j < n)) {
                                                        long r = scr_scroll_bot;
                                                        while ((r > scr_cur_y)) {
                                                            long dst = (r * COLS);
                                                            long src = ((r - 1) * COLS);
                                                            long c = 0;
                                                            while ((c < COLS)) {
                                                                _AD(scr_cells)[(dst + c)] = _AD(scr_cells)[(src + c)];
                                                                _AD(scr_fg)[(dst + c)] = _AD(scr_fg)[(src + c)];
                                                                _AD(scr_bg)[(dst + c)] = _AD(scr_bg)[(src + c)];
                                                                _AD(scr_flags)[(dst + c)] = _AD(scr_flags)[(src + c)];
                                                                c = (c + 1);
                                                            }
                                                            r = (r - 1);
                                                        }
                                                        long base = (scr_cur_y * COLS);
                                                        long c = 0;
                                                        while ((c < COLS)) {
                                                            _AD(scr_cells)[(base + c)] = 32;
                                                            _AD(scr_fg)[(base + c)] = 7;
                                                            _AD(scr_bg)[(base + c)] = 0;
                                                            _AD(scr_flags)[(base + c)] = 0;
                                                            c = (c + 1);
                                                        }
                                                        j = (j + 1);
                                                    }
                                                } else {
                                                    if ((b == 77)) {
                                                        long dr = scr_cur_y;
                                                        while ((dr <= scr_scroll_bot)) {
                                                            (void)(scr_mark_dirty(dr));
                                                            dr = (dr + 1);
                                                        }
                                                        long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                                                        long j = 0;
                                                        while ((j < n)) {
                                                            long r = scr_cur_y;
                                                            while ((r < scr_scroll_bot)) {
                                                                long dst = (r * COLS);
                                                                long src = ((r + 1) * COLS);
                                                                long c = 0;
                                                                while ((c < COLS)) {
                                                                    _AD(scr_cells)[(dst + c)] = _AD(scr_cells)[(src + c)];
                                                                    _AD(scr_fg)[(dst + c)] = _AD(scr_fg)[(src + c)];
                                                                    _AD(scr_bg)[(dst + c)] = _AD(scr_bg)[(src + c)];
                                                                    _AD(scr_flags)[(dst + c)] = _AD(scr_flags)[(src + c)];
                                                                    c = (c + 1);
                                                                }
                                                                r = (r + 1);
                                                            }
                                                            long base = (scr_scroll_bot * COLS);
                                                            long c = 0;
                                                            while ((c < COLS)) {
                                                                _AD(scr_cells)[(base + c)] = 32;
                                                                _AD(scr_fg)[(base + c)] = 7;
                                                                _AD(scr_bg)[(base + c)] = 0;
                                                                _AD(scr_flags)[(base + c)] = 0;
                                                                c = (c + 1);
                                                            }
                                                            j = (j + 1);
                                                        }
                                                    } else {
                                                        if ((b == 80)) {
                                                            (void)(scr_mark_dirty(scr_cur_y));
                                                            long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                                                            long row_s = (scr_cur_y * COLS);
                                                            long i = scr_cur_x;
                                                            while ((i < (COLS - n))) {
                                                                _AD(scr_cells)[(row_s + i)] = _AD(scr_cells)[((row_s + i) + n)];
                                                                _AD(scr_fg)[(row_s + i)] = _AD(scr_fg)[((row_s + i) + n)];
                                                                _AD(scr_bg)[(row_s + i)] = _AD(scr_bg)[((row_s + i) + n)];
                                                                _AD(scr_flags)[(row_s + i)] = _AD(scr_flags)[((row_s + i) + n)];
                                                                i = (i + 1);
                                                            }
                                                            long j = (COLS - n);
                                                            if ((j < scr_cur_x)) {
                                                                j = scr_cur_x;
                                                            }
                                                            while ((j < COLS)) {
                                                                _AD(scr_cells)[(row_s + j)] = 32;
                                                                _AD(scr_fg)[(row_s + j)] = 7;
                                                                _AD(scr_bg)[(row_s + j)] = 0;
                                                                _AD(scr_flags)[(row_s + j)] = 0;
                                                                j = (j + 1);
                                                            }
                                                        } else {
                                                            if ((b == 64)) {
                                                                (void)(scr_mark_dirty(scr_cur_y));
                                                                long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                                                                long row_s = (scr_cur_y * COLS);
                                                                long i = (COLS - 1);
                                                                while ((i >= (scr_cur_x + n))) {
                                                                    _AD(scr_cells)[(row_s + i)] = _AD(scr_cells)[((row_s + i) - n)];
                                                                    _AD(scr_fg)[(row_s + i)] = _AD(scr_fg)[((row_s + i) - n)];
                                                                    _AD(scr_bg)[(row_s + i)] = _AD(scr_bg)[((row_s + i) - n)];
                                                                    _AD(scr_flags)[(row_s + i)] = _AD(scr_flags)[((row_s + i) - n)];
                                                                    i = (i - 1);
                                                                }
                                                                long j = scr_cur_x;
                                                                while ((j < (scr_cur_x + n))) {
                                                                    if ((j < COLS)) {
                                                                        _AD(scr_cells)[(row_s + j)] = 32;
                                                                        _AD(scr_fg)[(row_s + j)] = 7;
                                                                        _AD(scr_bg)[(row_s + j)] = 0;
                                                                        _AD(scr_flags)[(row_s + j)] = 0;
                                                                    }
                                                                    j = (j + 1);
                                                                }
                                                            } else {
                                                                if ((b == 83)) {
                                                                    long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                                                                    long j = 0;
                                                                    while ((j < n)) {
                                                                        (void)(scr_scroll_up());
                                                                        j = (j + 1);
                                                                    }
                                                                } else {
                                                                    if ((b == 84)) {
                                                                        long n = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (1));
                                                                        long j = 0;
                                                                        while ((j < n)) {
                                                                            (void)(scr_scroll_down());
                                                                            j = (j + 1);
                                                                        }
                                                                    } else {
                                                                        if ((b == 114)) {
                                                                            long top = ((((vt_n > 0)) ? (_AD(vt_params)[0]) : (1)) - 1);
                                                                            long bot = ((((vt_n > 1)) ? (_AD(vt_params)[1]) : (ROWS)) - 1);
                                                                            if ((top < 0)) {
                                                                                top = 0;
                                                                            }
                                                                            if ((bot >= ROWS)) {
                                                                                bot = (ROWS - 1);
                                                                            }
                                                                            scr_scroll_top = top;
                                                                            scr_scroll_bot = bot;
                                                                            scr_cur_x = 0;
                                                                            scr_cur_y = 0;
                                                                        } else {
                                                                            if ((b == 104)) {
                                                                                if ((vt_private == 1)) {
                                                                                    long pn = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (0));
                                                                                    if ((pn == 1049)) {
                                                                                        (void)(enter_alt_screen(1, 1));
                                                                                    } else {
                                                                                        if ((pn == 1047)) {
                                                                                            (void)(enter_alt_screen(0, 1));
                                                                                        } else {
                                                                                            if ((pn == 47)) {
                                                                                                (void)(enter_alt_screen(0, 0));
                                                                                            } else {
                                                                                                if ((pn == 1048)) {
                                                                                                    alt_saved_cur_x = scr_cur_x;
                                                                                                    alt_saved_cur_y = scr_cur_y;
                                                                                                    alt_saved_fg = cur_fg;
                                                                                                    alt_saved_bg = cur_bg;
                                                                                                    alt_saved_bold = cur_bold;
                                                                                                    alt_saved_underline = cur_underline;
                                                                                                    alt_saved_inverse = cur_inverse;
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                }
                                                                            } else {
                                                                                if ((b == 108)) {
                                                                                    if ((vt_private == 1)) {
                                                                                        long pn = (((vt_n > 0)) ? (_AD(vt_params)[0]) : (0));
                                                                                        if ((pn == 1049)) {
                                                                                            (void)(leave_alt_screen(1));
                                                                                        } else {
                                                                                            if ((pn == 1047)) {
                                                                                                (void)(leave_alt_screen(0));
                                                                                            } else {
                                                                                                if ((pn == 47)) {
                                                                                                    (void)(leave_alt_screen(0));
                                                                                                } else {
                                                                                                    if ((pn == 1048)) {
                                                                                                        scr_cur_x = alt_saved_cur_x;
                                                                                                        scr_cur_y = alt_saved_cur_y;
                                                                                                        cur_fg = alt_saved_fg;
                                                                                                        cur_bg = alt_saved_bg;
                                                                                                        cur_bold = alt_saved_bold;
                                                                                                        cur_underline = alt_saved_underline;
                                                                                                        cur_inverse = alt_saved_inverse;
                                                                                                    }
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                } else {
                                                                                    if ((b == 115)) {
                                                                                        saved_cur_x = scr_cur_x;
                                                                                        saved_cur_y = scr_cur_y;
                                                                                    } else {
                                                                                        if ((b == 117)) {
                                                                                            scr_cur_x = saved_cur_x;
                                                                                            scr_cur_y = saved_cur_y;
                                                                                        } else {
                                                                                            if ((b == 110)) {
                                                                                                long pn = vt_csi_get(0, 0);
                                                                                                if ((pn == 6)) {
                                                                                                    long r = (scr_cur_y + 1);
                                                                                                    long c = (scr_cur_x + 1);
                                                                                                    (void)(hexa_reply_reset());
                                                                                                    (void)(hexa_reply_push(27));
                                                                                                    (void)(hexa_reply_push(91));
                                                                                                    if ((r >= 100)) {
                                                                                                        (void)(hexa_reply_push((48 + (r / 100))));
                                                                                                    }
                                                                                                    if ((r >= 10)) {
                                                                                                        (void)(hexa_reply_push(((48 + (r / 10)) - ((r / 100) * 10))));
                                                                                                    }
                                                                                                    (void)(hexa_reply_push(((48 + r) - ((r / 10) * 10))));
                                                                                                    (void)(hexa_reply_push(59));
                                                                                                    if ((c >= 100)) {
                                                                                                        (void)(hexa_reply_push((48 + (c / 100))));
                                                                                                    }
                                                                                                    if ((c >= 10)) {
                                                                                                        (void)(hexa_reply_push(((48 + (c / 10)) - ((c / 100) * 10))));
                                                                                                    }
                                                                                                    (void)(hexa_reply_push(((48 + c) - ((c / 10) * 10))));
                                                                                                    (void)(hexa_reply_push(82));
                                                                                                    (void)(hexa_reply_flush());
                                                                                                } else {
                                                                                                    if ((pn == 5)) {
                                                                                                        (void)(hexa_reply_reset());
                                                                                                        (void)(hexa_reply_push(27));
                                                                                                        (void)(hexa_reply_push(91));
                                                                                                        (void)(hexa_reply_push(48));
                                                                                                        (void)(hexa_reply_push(110));
                                                                                                        (void)(hexa_reply_flush());
                                                                                                    }
                                                                                                }
                                                                                            } else {
                                                                                                if ((b == 99)) {
                                                                                                    if ((vt_private == 0)) {
                                                                                                        (void)(hexa_reply_reset());
                                                                                                        (void)(hexa_reply_push(27));
                                                                                                        (void)(hexa_reply_push(91));
                                                                                                        (void)(hexa_reply_push(63));
                                                                                                        (void)(hexa_reply_push(54));
                                                                                                        (void)(hexa_reply_push(50));
                                                                                                        (void)(hexa_reply_push(59));
                                                                                                        (void)(hexa_reply_push(52));
                                                                                                        (void)(hexa_reply_push(99));
                                                                                                        (void)(hexa_reply_flush());
                                                                                                    }
                                                                                                }
                                                                                            }
                                                                                        }
                                                                                    }
                                                                                }
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

long scr_feed_byte(long b) {
    if ((vt_state == 0)) {
        long cls = _AD(vt_ground)[b];
        if ((cls == 0)) {
            (void)(scr_put(b));
        } else {
            if ((cls == 1)) {
                utf8_cp = 0;
                utf8_remain = 0;
                vt_state = 1;
            } else {
                if ((cls == 2)) {
                    scr_cur_x = 0;
                } else {
                    if ((cls == 3)) {
                        scr_cur_y = (scr_cur_y + 1);
                        if ((scr_cur_y > scr_scroll_bot)) {
                            (void)(scr_scroll_up());
                            scr_cur_y = scr_scroll_bot;
                        }
                    } else {
                        if ((cls == 4)) {
                            scr_cur_x = (scr_cur_x - 1);
                            if ((scr_cur_x < 0)) {
                                scr_cur_x = 0;
                            }
                        } else {
                            if ((cls == 5)) {
                                long rem = (scr_cur_x - ((scr_cur_x / 8) * 8));
                                scr_cur_x = (scr_cur_x + (8 - rem));
                                if ((scr_cur_x >= COLS)) {
                                    scr_cur_x = (COLS - 1);
                                }
                            } else {
                                if ((cls == 11)) {
                                    if ((utf8_remain > 0)) {
                                        utf8_cp = ((utf8_cp * 64) + (b - 128));
                                        utf8_remain = (utf8_remain - 1);
                                        if ((utf8_remain == 0)) {
                                            (void)(scr_put(utf8_cp));
                                        }
                                    }
                                } else {
                                    if (((cls >= 8) && (cls <= 10))) {
                                        utf8_cp = (b - _AD(vt_utf8_base)[cls]);
                                        utf8_remain = _AD(vt_utf8_remain)[cls];
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return 0;
    }
    if ((vt_state == 1)) {
        if ((b == 91)) {
            (void)(vt_csi_reset());
            vt_state = 2;
        } else {
            if ((b == 93)) {
                osc_num = 0;
                osc_title_bytes = hexa_arr_new();
                vt_state = 3;
            } else {
                if ((b == 55)) {
                    saved_cur_x = scr_cur_x;
                    saved_cur_y = scr_cur_y;
                    vt_state = 0;
                } else {
                    if ((b == 56)) {
                        scr_cur_x = saved_cur_x;
                        scr_cur_y = saved_cur_y;
                        vt_state = 0;
                    } else {
                        if ((b == 77)) {
                            if ((scr_cur_y == scr_scroll_top)) {
                                (void)(scr_scroll_down());
                            } else {
                                scr_cur_y = (scr_cur_y - 1);
                                if ((scr_cur_y < 0)) {
                                    scr_cur_y = 0;
                                }
                            }
                            vt_state = 0;
                        } else {
                            if ((b == 40)) {
                                vt_state = 5;
                            } else {
                                if ((b == 41)) {
                                    vt_state = 5;
                                } else {
                                    if ((b == 99)) {
                                        (void)(scr_init());
                                        cur_fg = 7;
                                        cur_bg = 0;
                                        cur_bold = 0;
                                        cur_underline = 0;
                                        cur_inverse = 0;
                                        cur_charset = 0;
                                        vt_state = 0;
                                    } else {
                                        vt_state = 0;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return 0;
    }
    if ((vt_state == 2)) {
        if ((b == 63)) {
            vt_private = 1;
            return 0;
        }
        if ((b >= 48)) {
            if ((b <= 57)) {
                vt_param = ((vt_param * 10) + (b - 48));
                vt_param_started = 1;
                return 0;
            }
        }
        if ((b == 59)) {
            (void)(vt_csi_flush());
            return 0;
        }
        if ((b >= 64)) {
            if ((b <= 126)) {
                (void)(csi_dispatch(b));
                vt_state = 0;
                return 0;
            }
        }
        return 0;
    }
    if ((vt_state == 3)) {
        if ((b >= 48)) {
            if ((b <= 57)) {
                osc_num = ((osc_num * 10) + (b - 48));
                return 0;
            }
        }
        if ((b == 59)) {
            vt_state = 4;
            return 0;
        }
        if ((b == 7)) {
            vt_state = 0;
            return 0;
        }
        if ((b == 27)) {
            vt_state = 0;
            return 0;
        }
        return 0;
    }
    if ((vt_state == 4)) {
        if ((b == 7)) {
            if ((osc_num <= 2)) {
                (void)(hexa_appkit_term_title_reset());
                long i = 0;
                while ((i < _AN(osc_title_bytes))) {
                    (void)(hexa_appkit_term_title_push(_AD(osc_title_bytes)[i]));
                    i = (i + 1);
                }
                (void)(hexa_appkit_term_title_apply());
            }
            if ((osc_num == 7)) {
                (void)(hexa_appkit_cwd_reset());
                long i = 0;
                while ((i < _AN(osc_title_bytes))) {
                    (void)(hexa_appkit_cwd_push(_AD(osc_title_bytes)[i]));
                    i = (i + 1);
                }
                (void)(hexa_appkit_cwd_apply());
            }
            vt_state = 0;
            return 0;
        }
        if ((b == 27)) {
            if ((osc_num <= 2)) {
                (void)(hexa_appkit_term_title_reset());
                long i = 0;
                while ((i < _AN(osc_title_bytes))) {
                    (void)(hexa_appkit_term_title_push(_AD(osc_title_bytes)[i]));
                    i = (i + 1);
                }
                (void)(hexa_appkit_term_title_apply());
            }
            if ((osc_num == 7)) {
                (void)(hexa_appkit_cwd_reset());
                long i = 0;
                while ((i < _AN(osc_title_bytes))) {
                    (void)(hexa_appkit_cwd_push(_AD(osc_title_bytes)[i]));
                    i = (i + 1);
                }
                (void)(hexa_appkit_cwd_apply());
            }
            vt_state = 0;
            return 0;
        }
        if ((osc_num <= 2)) {
            osc_title_bytes = hexa_arr_push(osc_title_bytes, b);
        }
        if ((osc_num == 7)) {
            osc_title_bytes = hexa_arr_push(osc_title_bytes, b);
        }
        return 0;
    }
    if ((vt_state == 5)) {
        if ((b == 48)) {
            cur_charset = 1;
        } else {
            cur_charset = 0;
        }
        vt_state = 0;
        return 0;
    }
    return 0;
}

long sync_to_bridge() {
    long r = 0;
    while ((r < ROWS)) {
        if (((_AD(scr_dirty)[r] == 1) || (scr_all_dirty == 1))) {
            long c = 0;
            while ((c < COLS)) {
                long idx = ((r * COLS) + c);
                (void)(hexa_appkit_term_set_cell(r, c, _AD(scr_cells)[idx], _AD(scr_fg)[idx], _AD(scr_bg)[idx], _AD(scr_flags)[idx]));
                c = (c + 1);
            }
            _AD(scr_dirty)[r] = 0;
        }
        r = (r + 1);
    }
    scr_all_dirty = 0;
    (void)(hexa_appkit_term_set_cursor(scr_cur_y, scr_cur_x, 1));
    (void)(hexa_appkit_term_flush());
    return 0;
}

long scr_find_probe(long probe, long probe_len) {
    long bound = (TOTAL - probe_len);
    long i = 0;
    while ((i <= bound)) {
        long hit = 1;
        long j = 0;
        while ((j < probe_len)) {
            if ((_AD(scr_cells)[(i + j)] != _AD(probe)[j])) {
                hit = 0;
                j = probe_len;
            }
            j = (j + 1);
        }
        if ((hit == 1)) {
            return 1;
        }
        i = (i + 1);
    }
    return 0;
}

long self_test() {
    printf("%s\n", "[void-test] === SELF-TEST START ===");
    long pass = 0;
    long fail = 0;
    (void)(scr_init());
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(67));
    if ((_AD(scr_cells)[0] == 65)) {
        if ((_AD(scr_cells)[1] == 66)) {
            if ((_AD(scr_cells)[2] == 67)) {
                printf("%s\n", "[void-test] T1 PASS  VT print ABC");
                pass = (pass + 1);
            } else {
                printf("%s %ld\n", "[void-test] T1 FAIL  cell[2]=", (long)(_AD(scr_cells)[2]));
                fail = (fail + 1);
            }
        } else {
            printf("%s %ld\n", "[void-test] T1 FAIL  cell[1]=", (long)(_AD(scr_cells)[1]));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld\n", "[void-test] T1 FAIL  cell[0]=", (long)(_AD(scr_cells)[0]));
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(50));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(51));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(88));
    long idx2 = ((1 * COLS) + 2);
    if ((_AD(scr_cells)[idx2] == 88)) {
        printf("%s\n", "[void-test] T2 PASS  CUP + put X at (1,2)");
        pass = (pass + 1);
    } else {
        printf("%s %ld\n", "[void-test] T2 FAIL  cell=", (long)(_AD(scr_cells)[idx2]));
        fail = (fail + 1);
    }
    (void)(scr_init());
    cur_fg = 7;
    cur_bg = 0;
    cur_bold = 0;
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(51));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(109));
    (void)(scr_feed_byte(82));
    if ((_AD(scr_fg)[0] == 1)) {
        if ((_AD(scr_cells)[0] == 82)) {
            printf("%s\n", "[void-test] T3 PASS  SGR fg=1 (red)");
            pass = (pass + 1);
        } else {
            printf("%s %ld\n", "[void-test] T3 FAIL  cell=", (long)(_AD(scr_cells)[0]));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld\n", "[void-test] T3 FAIL  fg=", (long)(_AD(scr_fg)[0]));
        fail = (fail + 1);
    }
    (void)(scr_init());
    cur_fg = 7;
    cur_bg = 0;
    cur_bold = 0;
    cur_underline = 0;
    cur_inverse = 0;
    (void)(scr_feed_byte(65));
    scr_cur_y = (ROWS - 1);
    scr_cur_x = 0;
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(10));
    if ((scr_cur_y == (ROWS - 1))) {
        printf("%s\n", "[void-test] T4 PASS  scroll (cursor stays at bottom)");
        pass = (pass + 1);
    } else {
        printf("%s %ld\n", "[void-test] T4 FAIL  cur_y=", (long)(scr_cur_y));
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(50));
    (void)(scr_feed_byte(74));
    if ((_AD(scr_cells)[0] == 32)) {
        if ((_AD(scr_cells)[1] == 32)) {
            printf("%s\n", "[void-test] T5 PASS  ED erase all");
            pass = (pass + 1);
        } else {
            printf("%s %ld\n", "[void-test] T5 FAIL  cell[1]=", (long)(_AD(scr_cells)[1]));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld\n", "[void-test] T5 FAIL  cell[0]=", (long)(_AD(scr_cells)[0]));
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(67));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(50));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(75));
    if ((_AD(scr_cells)[0] == 65)) {
        if ((_AD(scr_cells)[1] == 32)) {
            if ((_AD(scr_cells)[2] == 32)) {
                printf("%s\n", "[void-test] T6 PASS  EL erase to EOL");
                pass = (pass + 1);
            } else {
                printf("%s %ld\n", "[void-test] T6 FAIL  cell[2]=", (long)(_AD(scr_cells)[2]));
                fail = (fail + 1);
            }
        } else {
            printf("%s %ld\n", "[void-test] T6 FAIL  cell[1]=", (long)(_AD(scr_cells)[1]));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld\n", "[void-test] T6 FAIL  cell[0]=", (long)(_AD(scr_cells)[0]));
        fail = (fail + 1);
    }
    (void)(scr_init());
    cur_fg = 7;
    cur_bg = 0;
    cur_bold = 0;
    cur_underline = 0;
    cur_inverse = 0;
    vt_state = 0;
    (void)(hexa_sh_reset_accum());
    long m = hexa_sh_spawn();
    if ((m < 0)) {
        printf("%s\n", "[void-test] T7 FAIL  PTY spawn");
        fail = (fail + 1);
    } else {
        (void)(hexa_sh_write_canned(m, 0));
        (void)(hexa_term_drain_master(m, 500));
        (void)(hexa_sh_write_canned(m, 1));
        (void)(hexa_term_drain_master(m, 500));
        long accum_n = hexa_sh_accum_len_q();
        long fi = 0;
        while ((fi < accum_n)) {
            long b = hexa_sh_accum_byte_at(fi);
            (void)(scr_feed_byte(b));
            fi = (fi + 1);
        }
        (void)(hexa_sh_reap());
        long probe = hexa_arr_lit((long[]){104, 101, 120, 97, 45, 116, 101, 114, 109}, 9);
        long found = scr_find_probe(probe, 9);
        if ((found == 1)) {
            printf("%s %ld %s\n", "[void-test] T7 PASS  PTY→VT→screen pipeline ('hexa-term' found, ", (long)(accum_n), " bytes)");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s\n", "[void-test] T7 FAIL  probe not found in screen (", (long)(accum_n), " bytes drained)");
            fail = (fail + 1);
        }
    }
    (void)(scr_init());
    vt_state = 0;
    osc_title_bytes = hexa_arr_new();
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(93));
    (void)(scr_feed_byte(48));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(67));
    (void)(scr_feed_byte(7));
    if ((_AN(osc_title_bytes) == 3)) {
        if ((_AD(osc_title_bytes)[0] == 65)) {
            printf("%s\n", "[void-test] T8 PASS  OSC 0 title parse (3 bytes)");
            pass = (pass + 1);
        } else {
            printf("%s %ld\n", "[void-test] T8 FAIL  title[0]=", (long)(_AD(osc_title_bytes)[0]));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld\n", "[void-test] T8 FAIL  title len=", (long)(_AN(osc_title_bytes)));
        fail = (fail + 1);
    }
    COLS = 120;
    ROWS = 40;
    TOTAL = (ROWS * COLS);
    (void)(scr_init());
    (void)(vt_reset_state());
    long t9i = 0;
    while ((t9i < 121)) {
        (void)(scr_feed_byte(65));
        t9i = (t9i + 1);
    }
    if ((scr_cur_y == 1)) {
        if ((scr_cur_x == 1)) {
            if ((_AD(scr_cells)[120] == 65)) {
                printf("%s\n", "[void-test] T9 PASS  dynamic grid 120x40 (wrap at col 120)");
                pass = (pass + 1);
            } else {
                printf("%s %ld\n", "[void-test] T9 FAIL  cell[120]=", (long)(_AD(scr_cells)[120]));
                fail = (fail + 1);
            }
        } else {
            printf("%s %ld\n", "[void-test] T9 FAIL  cur_x=", (long)(scr_cur_x));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T9 FAIL  cur_y=", (long)(scr_cur_y), " expected 1");
        fail = (fail + 1);
    }
    COLS = 80;
    ROWS = 24;
    TOTAL = 1920;
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(237));
    (void)(scr_feed_byte(149));
    (void)(scr_feed_byte(156));
    long han_cp = _AD(scr_cells)[0];
    if ((han_cp == 54620)) {
        printf("%s %ld %s\n", "[void-test] T10 PASS UTF-8 한 (U+D55C=", (long)(han_cp), ")");
        pass = (pass + 1);
    } else {
        printf("%s %ld %s\n", "[void-test] T10 FAIL  cp=", (long)(han_cp), " expected 54620");
        fail = (fail + 1);
    }
    COLS = 100;
    ROWS = 30;
    TOTAL = (ROWS * COLS);
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(hexa_sh_reset_accum());
    long m11 = hexa_sh_spawn();
    if ((m11 < 0)) {
        printf("%s\n", "[void-test] T11 FAIL  PTY spawn");
        fail = (fail + 1);
    } else {
        (void)(hexa_sh_write_canned(m11, 0));
        (void)(hexa_term_drain_master(m11, 500));
        (void)(hexa_sh_write_canned(m11, 1));
        (void)(hexa_term_drain_master(m11, 500));
        long a11 = hexa_sh_accum_len_q();
        long fi11 = 0;
        while ((fi11 < a11)) {
            long b11 = hexa_sh_accum_byte_at(fi11);
            (void)(scr_feed_byte(b11));
            fi11 = (fi11 + 1);
        }
        (void)(hexa_sh_reap());
        long probe11 = hexa_arr_lit((long[]){104, 101, 120, 97, 45, 116, 101, 114, 109}, 9);
        long found11 = scr_find_probe(probe11, 9);
        if ((found11 == 1)) {
            printf("%s %ld %s\n", "[void-test] T11 PASS PTY pipeline at 100x30 (", (long)(a11), " bytes)");
            pass = (pass + 1);
        } else {
            printf("%s\n", "[void-test] T11 FAIL  probe not found at 100x30");
            fail = (fail + 1);
        }
    }
    COLS = 80;
    ROWS = 24;
    TOTAL = 1920;
    long t12a = hexa_tab_new();
    long t12b = hexa_tab_new();
    long t12c = hexa_tab_new();
    long t12_count = hexa_tab_count();
    long t12_active = hexa_tab_get_active();
    (void)(hexa_tab_close(t12_active));
    long t12_count2 = hexa_tab_count();
    long t12_active2 = hexa_tab_get_active();
    if ((t12_count == 3)) {
        if ((t12_count2 == 2)) {
            if ((t12_active2 >= 0)) {
                printf("%s %ld %s\n", "[void-test] T12 PASS tab new/close (3→close→2, active=", (long)(t12_active2), ")");
                pass = (pass + 1);
            } else {
                printf("%s %ld\n", "[void-test] T12 FAIL  active after close=", (long)(t12_active2));
                fail = (fail + 1);
            }
        } else {
            printf("%s %ld\n", "[void-test] T12 FAIL  count after close=", (long)(t12_count2));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld\n", "[void-test] T12 FAIL  initial count=", (long)(t12_count));
        fail = (fail + 1);
    }
    (void)(hexa_tab_close(0));
    (void)(hexa_tab_close(0));
    COLS = 80;
    ROWS = 24;
    TOTAL = 1920;
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(54));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(54));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(50));
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(51));
    (void)(scr_feed_byte(67));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(52));
    (void)(scr_feed_byte(68));
    if ((scr_cur_y == 4)) {
        if ((scr_cur_x == 4)) {
            printf("%s\n", "[void-test] T13 PASS CUU/CUD/CUF/CUB (5,5)→(4,4)");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s\n", "[void-test] T13 FAIL  cur_x=", (long)(scr_cur_x), " expected 4");
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T13 FAIL  cur_y=", (long)(scr_cur_y), " expected 4");
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(52));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(56));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(115));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(117));
    if ((scr_cur_y == 3)) {
        if ((scr_cur_x == 7)) {
            printf("%s\n", "[void-test] T14 PASS save/restore cursor (3,7)");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s\n", "[void-test] T14 FAIL  cur_x=", (long)(scr_cur_x), " expected 7");
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T14 FAIL  cur_y=", (long)(scr_cur_y), " expected 3");
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(51));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(54));
    (void)(scr_feed_byte(114));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(51));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(90));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(54));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(10));
    if ((_AD(scr_cells)[0] == 90)) {
        if ((scr_scroll_top == 2)) {
            if ((scr_scroll_bot == 5)) {
                printf("%s\n", "[void-test] T15 PASS DECSTBM scroll region (row 0 intact)");
                pass = (pass + 1);
            } else {
                printf("%s %ld\n", "[void-test] T15 FAIL  scroll_bot=", (long)(scr_scroll_bot));
                fail = (fail + 1);
            }
        } else {
            printf("%s %ld\n", "[void-test] T15 FAIL  scroll_top=", (long)(scr_scroll_top));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T15 FAIL  row0[0]=", (long)(_AD(scr_cells)[0]), " expected 90 (Z)");
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(76));
    if ((_AD(scr_cells)[0] == 32)) {
        long r1 = (1 * COLS);
        if ((_AD(scr_cells)[r1] == 65)) {
            if ((_AD(scr_cells)[(r1 + 1)] == 66)) {
                printf("%s\n", "[void-test] T16 PASS IL insert line (AB pushed to row 1)");
                pass = (pass + 1);
            } else {
                printf("%s %ld\n", "[void-test] T16 FAIL  row1[1]=", (long)(_AD(scr_cells)[(r1 + 1)]));
                fail = (fail + 1);
            }
        } else {
            printf("%s %ld\n", "[void-test] T16 FAIL  row1[0]=", (long)(_AD(scr_cells)[r1]));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T16 FAIL  row0[0]=", (long)(_AD(scr_cells)[0]), " expected 32");
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(66));
    (void)(scr_feed_byte(67));
    (void)(scr_feed_byte(68));
    (void)(scr_feed_byte(69));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(50));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(50));
    (void)(scr_feed_byte(80));
    if ((_AD(scr_cells)[0] == 65)) {
        if ((_AD(scr_cells)[1] == 68)) {
            if ((_AD(scr_cells)[2] == 69)) {
                printf("%s\n", "[void-test] T17 PASS DCH delete 2 chars (ABCDE→ADE)");
                pass = (pass + 1);
            } else {
                printf("%s %ld %s\n", "[void-test] T17 FAIL  cell[2]=", (long)(_AD(scr_cells)[2]), " expected 69(E)");
                fail = (fail + 1);
            }
        } else {
            printf("%s %ld %s\n", "[void-test] T17 FAIL  cell[1]=", (long)(_AD(scr_cells)[1]), " expected 68(D)");
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T17 FAIL  cell[0]=", (long)(_AD(scr_cells)[0]), " expected 65(A)");
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(78));
    (void)(scr_feed_byte(79));
    (void)(scr_feed_byte(82));
    (void)(scr_feed_byte(77));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(63));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(48));
    (void)(scr_feed_byte(52));
    (void)(scr_feed_byte(57));
    (void)(scr_feed_byte(104));
    long t18_alt_ok = (((_AD(scr_cells)[0] == 32)) ? (1) : (0));
    (void)(scr_feed_byte(65));
    (void)(scr_feed_byte(76));
    (void)(scr_feed_byte(84));
    long t18_alt_write_ok = (((_AD(scr_cells)[0] == 65)) ? (1) : (0));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(63));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(48));
    (void)(scr_feed_byte(52));
    (void)(scr_feed_byte(57));
    (void)(scr_feed_byte(108));
    if ((t18_alt_ok == 1)) {
        if ((t18_alt_write_ok == 1)) {
            if ((_AD(scr_cells)[0] == 78)) {
                if ((_AD(scr_cells)[3] == 77)) {
                    if ((scr_cur_x == 10)) {
                        if ((scr_cur_y == 0)) {
                            if ((scr_is_alt == 0)) {
                                printf("%s\n", "[void-test] T18 PASS ?1049 alt screen save/restore");
                                pass = (pass + 1);
                            } else {
                                printf("%s %ld\n", "[void-test] T18 FAIL  scr_is_alt=", (long)(scr_is_alt));
                                fail = (fail + 1);
                            }
                        } else {
                            printf("%s %ld %s\n", "[void-test] T18 FAIL  cur_y=", (long)(scr_cur_y), " expected 0");
                            fail = (fail + 1);
                        }
                    } else {
                        printf("%s %ld %s\n", "[void-test] T18 FAIL  cur_x=", (long)(scr_cur_x), " expected 10");
                        fail = (fail + 1);
                    }
                } else {
                    printf("%s %ld %s\n", "[void-test] T18 FAIL  cell[3]=", (long)(_AD(scr_cells)[3]), " expected 77(M)");
                    fail = (fail + 1);
                }
            } else {
                printf("%s %ld %s\n", "[void-test] T18 FAIL  cell[0]=", (long)(_AD(scr_cells)[0]), " expected 78(N)");
                fail = (fail + 1);
            }
        } else {
            printf("%s %ld\n", "[void-test] T18 FAIL  alt write cell[0]=", (long)(_AD(scr_cells)[0]));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld\n", "[void-test] T18 FAIL  alt clear cell[0]=", (long)(_AD(scr_cells)[0]));
        fail = (fail + 1);
    }
    COLS = 80;
    ROWS = 24;
    TOTAL = 1920;
    (void)(scr_init());
    (void)(vt_reset_state());
    long t19_row = 0;
    while ((t19_row < 10)) {
        long t19_dig = (t19_row + 1);
        if ((t19_dig >= 10)) {
            t19_dig = 0;
        }
        (void)(scr_feed_byte(32));
        (void)(scr_feed_byte(32));
        (void)(scr_feed_byte(124));
        (void)(scr_feed_byte(32));
        (void)(scr_feed_byte((48 + t19_dig)));
        (void)(scr_feed_byte(32));
        (void)(scr_feed_byte(124));
        (void)(scr_feed_byte(32));
        (void)(scr_feed_byte(114));
        (void)(scr_feed_byte(111));
        (void)(scr_feed_byte(119));
        (void)(scr_feed_byte(95));
        (void)(scr_feed_byte((48 + t19_dig)));
        (void)(scr_feed_byte(32));
        (void)(scr_feed_byte(124));
        (void)(scr_feed_byte(13));
        (void)(scr_feed_byte(10));
        t19_row = (t19_row + 1);
    }
    long t19_fail = 0;
    long t19_r = 0;
    while ((t19_r < 10)) {
        long base = (t19_r * COLS);
        if ((_AD(scr_cells)[base] != 32)) {
            t19_fail = (t19_fail + 1);
        }
        if ((_AD(scr_cells)[(base + 1)] != 32)) {
            t19_fail = (t19_fail + 1);
        }
        if ((_AD(scr_cells)[(base + 2)] != 124)) {
            t19_fail = (t19_fail + 1);
        }
        t19_r = (t19_r + 1);
    }
    if ((t19_fail == 0)) {
        printf("%s\n", "[void-test] T19 PASS cl-table 10-row alignment (all rows start at col 2)");
        pass = (pass + 1);
    } else {
        printf("%s %ld %s\n", "[void-test] T19 FAIL  ", (long)(t19_fail), " cells misaligned");
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(226));
    (void)(scr_feed_byte(148));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(51));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(109));
    (void)(scr_feed_byte(65));
    if ((_AD(scr_cells)[0] == 65)) {
        if ((scr_cur_x == 1)) {
            printf("%s\n", "[void-test] T20 PASS utf8 state reset on ESC (A printed after interrupted UTF-8)");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s\n", "[void-test] T20 FAIL  cur_x=", (long)(scr_cur_x), " expected 1");
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T20 FAIL  cell[0]=", (long)(_AD(scr_cells)[0]), " expected 65(A)");
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(225));
    (void)(scr_feed_byte(132));
    (void)(scr_feed_byte(128));
    (void)(scr_feed_byte(225));
    (void)(scr_feed_byte(133));
    (void)(scr_feed_byte(161));
    (void)(scr_feed_byte(225));
    (void)(scr_feed_byte(134));
    (void)(scr_feed_byte(168));
    if ((_AD(scr_cells)[0] == 44033)) {
        if ((scr_cur_x == 2)) {
            printf("%s\n", "[void-test] T21 PASS Hangul NFD composed (U+1100+U+1161+U+11A8 -> U+AC01)");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s\n", "[void-test] T21 FAIL  cur_x=", (long)(scr_cur_x), " expected 2");
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T21 FAIL  cell[0]=", (long)(_AD(scr_cells)[0]), " expected 44033");
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(vt_reset_state());
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(51));
    (void)(scr_feed_byte(49));
    (void)(scr_feed_byte(109));
    (void)(scr_feed_byte(82));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(52));
    (void)(scr_feed_byte(52));
    (void)(scr_feed_byte(109));
    (void)(scr_feed_byte(75));
    if (((_AD(scr_cells)[0] == 82) && (_AD(scr_fg)[0] == 1))) {
        if (((_AD(scr_cells)[1] == 75) && (_AD(scr_bg)[1] == 4))) {
            printf("%s\n", "[void-test] T22 PASS SGR 3x/4x color cells (R red fg, K blue bg)");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s %ld\n", "[void-test] T22 FAIL  cell[1]=", (long)(_AD(scr_cells)[1]), " bg=", (long)(_AD(scr_bg)[1]));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s %ld\n", "[void-test] T22 FAIL  cell[0]=", (long)(_AD(scr_cells)[0]), " fg=", (long)(_AD(scr_fg)[0]));
        fail = (fail + 1);
    }
    (void)(scr_init());
    (void)(hexa_keybuf_clear());
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(52));
    (void)(scr_feed_byte(59));
    (void)(scr_feed_byte(56));
    (void)(scr_feed_byte(72));
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(54));
    (void)(scr_feed_byte(110));
    long t23_len = hexa_keybuf_len();
    if ((t23_len == 6)) {
        long t23_0 = hexa_keybuf_byte(0);
        long t23_1 = hexa_keybuf_byte(1);
        long t23_2 = hexa_keybuf_byte(2);
        long t23_3 = hexa_keybuf_byte(3);
        long t23_4 = hexa_keybuf_byte(4);
        long t23_5 = hexa_keybuf_byte(5);
        if (((((((t23_0 == 27) && (t23_1 == 91)) && (t23_2 == 52)) && (t23_3 == 59)) && (t23_4 == 56)) && (t23_5 == 82))) {
            printf("%s\n", "[void-test] T23 PASS DSR CSI 6n → CPR ESC[4;8R");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s %ld %s %ld %s %ld %s %ld %s %ld\n", "[void-test] T23 FAIL  response bytes=", (long)(t23_0), ",", (long)(t23_1), ",", (long)(t23_2), ",", (long)(t23_3), ",", (long)(t23_4), ",", (long)(t23_5));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T23 FAIL  keybuf len=", (long)(t23_len), " expected 6");
        fail = (fail + 1);
    }
    (void)(hexa_keybuf_clear());
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(99));
    long t24_len = hexa_keybuf_len();
    if ((t24_len == 8)) {
        long t24_0 = hexa_keybuf_byte(0);
        long t24_1 = hexa_keybuf_byte(1);
        long t24_2 = hexa_keybuf_byte(2);
        long t24_7 = hexa_keybuf_byte(7);
        if (((((t24_0 == 27) && (t24_1 == 91)) && (t24_2 == 63)) && (t24_7 == 99))) {
            printf("%s\n", "[void-test] T24 PASS DA1 CSI c → ESC[?62;4c");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s %ld %s %ld %s %ld\n", "[void-test] T24 FAIL  response bytes=", (long)(t24_0), ",", (long)(t24_1), ",", (long)(t24_2), "...", (long)(t24_7));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T24 FAIL  keybuf len=", (long)(t24_len), " expected 8");
        fail = (fail + 1);
    }
    (void)(hexa_keybuf_clear());
    (void)(scr_feed_byte(27));
    (void)(scr_feed_byte(91));
    (void)(scr_feed_byte(53));
    (void)(scr_feed_byte(110));
    long t25_len = hexa_keybuf_len();
    if ((t25_len == 4)) {
        long t25_0 = hexa_keybuf_byte(0);
        long t25_3 = hexa_keybuf_byte(3);
        if (((t25_0 == 27) && (t25_3 == 110))) {
            printf("%s\n", "[void-test] T25 PASS DSR CSI 5n → ESC[0n (status OK)");
            pass = (pass + 1);
        } else {
            printf("%s %ld %s %ld\n", "[void-test] T25 FAIL  response bytes=", (long)(t25_0), "...", (long)(t25_3));
            fail = (fail + 1);
        }
    } else {
        printf("%s %ld %s\n", "[void-test] T25 FAIL  keybuf len=", (long)(t25_len), " expected 4");
        fail = (fail + 1);
    }
    printf("%s\n", "");
    printf("%s %ld %s %ld %s\n", "[void-test] ", (long)(pass), "/", (long)((pass + fail)), " passed");
    if ((fail == 0)) {
        printf("%s\n", "[void-test] === ALL TESTS PASS ===");
    } else {
        printf("%s %ld %s\n", "[void-test] === ", (long)(fail), " FAILURES ===");
    }
    (void)(scr_init());
    long bench_bytes = 100000;
    long t0 = clock_us();
    long bi = 0;
    while ((bi < bench_bytes)) {
        long bb = (32 + (bi - ((bi / 94) * 94)));
        (void)(scr_feed_byte(bb));
        bi = (bi + 1);
    }
    long t1 = clock_us();
    long us = (t1 - t0);
    printf("%s %ld %s %ld %s\n", "[void-bench] scr_feed_byte: ", (long)(bench_bytes), " bytes in ", (long)(us), " us");
    if ((us > 0)) {
        long mbps = (bench_bytes / us);
        printf("%s %ld %s\n", "[void-bench] throughput: ~", (long)(mbps), " MB/s");
    }
    (void)(scr_mark_all_dirty());
    long t2 = clock_us();
    long si = 0;
    while ((si < 100)) {
        (void)(scr_mark_all_dirty());
        (void)(sync_to_bridge());
        si = (si + 1);
    }
    long t3 = clock_us();
    long sync_us = (t3 - t2);
    printf("%s %ld %s\n", "[void-bench] sync_to_bridge (full, 100x): ", (long)(sync_us), " us");
    long t4 = clock_us();
    long di = 0;
    while ((di < 100)) {
        (void)(scr_mark_dirty(0));
        (void)(sync_to_bridge());
        di = (di + 1);
    }
    long t5 = clock_us();
    long delta_us = (t5 - t4);
    printf("%s %ld %s\n", "[void-bench] sync_to_bridge (1-row delta, 100x): ", (long)(delta_us), " us");
    return fail;
}

long load_from_bridge() {
    long i = 0;
    while ((i < TOTAL)) {
        _AD(scr_cells)[i] = hexa_tab_cell_cp(i);
        _AD(scr_fg)[i] = hexa_tab_cell_fg(i);
        _AD(scr_bg)[i] = hexa_tab_cell_bg(i);
        _AD(scr_flags)[i] = hexa_tab_cell_flags(i);
        i = (i + 1);
    }
    (void)(scr_mark_all_dirty());
    scr_cur_x = hexa_tab_cursor_x();
    scr_cur_y = hexa_tab_cursor_y();
    return 0;
}

long vt_reset_state() {
    vt_state = 0;
    vt_param = 0;
    vt_params = hexa_arr_new();
    vt_param_started = 0;
    vt_private = 0;
    cur_fg = 7;
    cur_bg = 0;
    cur_bold = 0;
    cur_underline = 0;
    cur_inverse = 0;
    osc_num = 0;
    osc_title_bytes = hexa_arr_new();
    saved_cur_x = 0;
    saved_cur_y = 0;
    cur_charset = 0;
    scr_scroll_top = 0;
    scr_scroll_bot = (ROWS - 1);
    utf8_cp = 0;
    utf8_remain = 0;
    scr_is_alt = 0;
    alt_saved_cur_x = 0;
    alt_saved_cur_y = 0;
    g_hangul_L = (-1);
    g_hangul_V = (-1);
    return 0;
}

long hexa_user_main() {
    if ((hexa_check_test_mode() == 1)) {
        return self_test();
    }
    (void)(scr_init());
    long init_r = hexa_appkit_init_term(0, 0, 14);
    if ((init_r < 0)) {
        return 1;
    }
    COLS = hexa_appkit_term_get_cols();
    ROWS = hexa_appkit_term_get_rows();
    TOTAL = (ROWS * COLS);
    (void)(scr_init());
    long t0 = hexa_tab_new();
    if ((t0 < 0)) {
        printf("%s\n", "[void] FAIL: initial tab");
        return 1;
    }
    long running = 1;
    while ((running == 1)) {
        long quit = hexa_appkit_term_poll();
        if ((quit == 1)) {
            running = 0;
        }
        long cmd = hexa_tab_poll_cmd();
        if ((cmd == 1)) {
            (void)(sync_to_bridge());
            long nt = hexa_tab_new();
            if ((nt >= 0)) {
                (void)(scr_init());
                (void)(vt_reset_state());
            }
        }
        if ((cmd == 2)) {
            (void)(sync_to_bridge());
            long cur_tab = hexa_tab_get_active();
            long active = hexa_tab_close(cur_tab);
            if ((hexa_tab_count() == 0)) {
                running = 0;
            } else {
                (void)(load_from_bridge());
                (void)(vt_reset_state());
            }
        }
        if ((cmd == 3)) {
            (void)(load_from_bridge());
            (void)(vt_reset_state());
            (void)(hexa_tab_nudge_pty());
        }
        if ((hexa_appkit_term_check_resize() == 1)) {
            long new_r = hexa_appkit_term_get_rows();
            long new_c = hexa_appkit_term_get_cols();
            if ((new_r != ROWS)) {
                ROWS = new_r;
            }
            if ((new_c != COLS)) {
                COLS = new_c;
            }
            TOTAL = (ROWS * COLS);
            (void)(scr_init());
            (void)(vt_reset_state());
            long rfd = hexa_tab_get_pty();
            if ((rfd >= 0)) {
                (void)(hexa_pty_resize(rfd, ROWS, COLS));
            }
        }
        long m = hexa_tab_get_pty();
        if ((m < 0)) {
            (void)(hexa_sleep_us(10000));
        } else {
            (void)(hexa_keys_to_pty(m));
            long drained = 0;
            long drain_cap = 65536;
            long drain_tmo = 5;
            long drain_more = 1;
            while ((drain_more == 1)) {
                long nread = hexa_pty_poll_read(m, drain_tmo);
                drain_tmo = 0;
                if ((nread > 0)) {
                    long i = 0;
                    while ((i < nread)) {
                        long b = hexa_pty_read_byte(i);
                        if ((b >= 0)) {
                            (void)(scr_feed_byte(b));
                        }
                        i = (i + 1);
                    }
                    drained = (drained + nread);
                    if ((drained >= drain_cap)) {
                        drain_more = 0;
                    }
                } else {
                    drain_more = 0;
                }
            }
            if ((drained > 0)) {
                (void)(sync_to_bridge());
            }
            if ((drained == 0)) {
                (void)(hexa_sleep_us(2000));
            }
        }
    }
    return 0;
}


int main(int argc, char** argv) {
    hexa_main_argc = argc; hexa_main_argv = argv;
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    /* unsupported stmt */
    scr_cells = hexa_arr_new();
    scr_fg = hexa_arr_new();
    scr_bg = hexa_arr_new();
    scr_flags = hexa_arr_new();
    scr_dirty = hexa_arr_new();
    alt_cells = hexa_arr_new();
    alt_fg = hexa_arr_new();
    alt_bg = hexa_arr_new();
    alt_flags = hexa_arr_new();
    vt_params = hexa_arr_new();
    osc_title_bytes = hexa_arr_new();
    vt_ground = hexa_arr_lit((long[]){(long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(6), (long)(4), (long)(5), (long)(3), (long)(7), (long)(7), (long)(2), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(7), (long)(1), (long)(7), (long)(7), (long)(7), (long)(7), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(11), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(8), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(9), (long)(10), (long)(10), (long)(10), (long)(10), (long)(10), (long)(10), (long)(10), (long)(10), (long)(12), (long)(12), (long)(12), (long)(12), (long)(12), (long)(12), (long)(12), (long)(12)}, 256);
    vt_utf8_base = hexa_arr_lit((long[]){(long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(192), (long)(224), (long)(240), (long)(0), (long)(0)}, 13);
    vt_utf8_remain = hexa_arr_lit((long[]){(long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(1), (long)(2), (long)(3), (long)(0), (long)(0)}, 13);
    wide_pages = hexa_arr_lit((long[]){(long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(2), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(2), (long)(1), (long)(2), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(2), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(2), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(1), (long)(2), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(0), (long)(1), (long)(1), (long)(0), (long)(0), (long)(0), (long)(2), (long)(2)}, 256);
    g_hangul_L = (-1);
    g_hangul_V = (-1);
    hexa_user_main();
    return 0;
}
