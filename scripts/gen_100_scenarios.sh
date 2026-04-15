#!/usr/bin/env bash
# Generates 100 headless scenarios exercising every known pitfall category.
# Each scenario is a tiny byte stream fed through the VT parser via
# VOID_HEADLESS_FEED. Goldens bootstrapped with UPDATE_GOLDEN=1 after a
# harness-approved binary exists.
#
# Categories (10 each):
#   sgr_* (10)        fg/bg/bold/256/RGB/reset
#   cursor_* (10)     CUU/CUD/CUF/CUB/CUP/CHA/VPA/HVP/SCP/RCP
#   erase_* (10)      ED/EL/ECH edges
#   scroll_* (10)     DECSTBM / SU / SD / LF scroll
#   idel_* (10)       IL/DL/ICH/DCH/TAB/BS/autowrap
#   cjk_* (10)        Hangul/kanji/mixed
#   emoji_* (10)      VP-08 SMP pictograph + surrogate
#   box_* (10)        U+2500 box drawing / frames
#   tui_* (10)        spinner / progress bar / full redraw
#   edge_* (10)       NUL / invalid UTF-8 / RIS / SCP / long line

set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)/tests/headless"
mkdir -p "$DIR"

write() {  # write <name> <python-bytes-expression>
    /usr/bin/python3 -c "import sys; sys.stdout.buffer.write($2)" > "$DIR/$1.in"
}

# ── SGR (10) ──
write sgr_fg_red            "b'\\x1b[31mR\\x1b[0m'"
write sgr_bg_blue           "b'\\x1b[44mX\\x1b[0m'"
write sgr_bold_on_off       "b'\\x1b[1mB\\x1b[22mb'"
write sgr_256_fg            "b'\\x1b[38;5;196mR\\x1b[0m'"
write sgr_256_bg            "b'\\x1b[48;5;21mB\\x1b[0m'"
write sgr_rgb_fg            "b'\\x1b[38;2;255;128;0mR\\x1b[0m'"
write sgr_rgb_bg            "b'\\x1b[48;2;0;128;255mB\\x1b[0m'"
write sgr_multi_combined    "b'\\x1b[1;31;44mM\\x1b[0m'"
write sgr_reset_default     "b'\\x1b[1;31;44mA\\x1b[mN'"
write sgr_bright_fg         "b'\\x1b[91mR\\x1b[0m'"

# ── Cursor movement (10) ──
write cursor_cup_3_5        "b'\\x1b[3;5HX'"
write cursor_up             "b'ABC\\x1b[ABX'"
write cursor_down           "b'A\\x1b[BB\\x1b[BC'"
write cursor_forward        "b'A\\x1b[3CB'"
write cursor_back           "b'ABCD\\x1b[2DX'"
write cursor_cha_col        "b'ABCDE\\x1b[3GZ'"
write cursor_vpa_row        "b'\\x1b[5dZ'"
write cursor_hvp_same       "b'\\x1b[4;8fQ'"
write cursor_scp_rcp        "b'AB\\x1b[sCD\\x1b[uZ'"
write cursor_home_nop       "b'\\x1b[HQ'"

# ── Erase (10) ──
write erase_ed_all          "b'ABC\\x1b[2JXYZ'"
write erase_ed_below        "b'line0\\r\\nline1\\r\\nline2\\x1b[1;1H\\x1b[0J'"
write erase_ed_above        "b'ABCDE\\x1b[1;3H\\x1b[1J'"
write erase_ed_scrollback   "b'A\\x1b[3JB'"
write erase_el_end          "b'ABCDE\\x1b[1;3H\\x1b[0K'"
write erase_el_start        "b'ABCDE\\x1b[1;3H\\x1b[1K'"
write erase_el_all          "b'ABCDE\\x1b[2K'"
write erase_ech_2           "b'ABCDE\\x1b[1;2H\\x1b[2X'"
write erase_ech_clamp       "b'ABCDE\\x1b[1;3H\\x1b[999X'"
write erase_el_end_mid      "b'xxxxxxxx\\x1b[1;4H\\x1b[0KY'"

# ── Scroll (10) ──
write scroll_lf_wrap        "$(/usr/bin/python3 -c "print(repr(b'L1\\r\\n' * 26))")"
write scroll_su_2           "b'A\\r\\nB\\x1b[2S'"
write scroll_sd_1           "b'A\\r\\nB\\x1b[1T'"
write scroll_region_simple  "b'\\x1b[3;6rA\\r\\nB\\r\\nC\\r\\nD\\r\\nE'"
write scroll_region_full    "b'\\x1b[3;6r\\x1b[3;1H\\r\\n\\r\\n\\r\\nX'"
write scroll_decstbm_clear  "b'\\x1b[5;10r\\x1b[rX'"
write scroll_ri_reverse     "b'\\x1b[1;1HA\\x1bM'"
write scroll_ind_forward    "b'line0\\r\\nline1\\x1bD'"
write scroll_nel_next       "b'A\\x1bEX'"
write scroll_many_lines     "$(/usr/bin/python3 -c "print(repr(b'row\\r\\n'*50))")"

# ── Insert/delete/tab/bs/autowrap (10) ──
write idel_ich_2            "b'ABCDE\\x1b[1;2H\\x1b[2@'"
write idel_dch_2            "b'ABCDE\\x1b[1;2H\\x1b[2P'"
write idel_il_1             "b'R0\\r\\nR1\\r\\nR2\\x1b[1;1H\\x1b[1L'"
write idel_dl_1             "b'R0\\r\\nR1\\r\\nR2\\x1b[1;1H\\x1b[1M'"
write idel_tab_0_8          "b'\\tX'"
write idel_tab_5_8          "b'AAAAA\\tX'"
write idel_bs_mid           "b'ABCDE\\x08\\x08X'"
write idel_bs_col0          "b'\\x08\\x08\\x08X'"
write idel_autowrap_80      "$(/usr/bin/python3 -c "print(repr(b'A'*81))")"
write idel_autowrap_cjk     "$(/usr/bin/python3 -c "print(repr(('가'*45).encode('utf-8')))")"

# ── CJK wide (10) ──
write cjk_hangul_short      "$(/usr/bin/python3 -c "print(repr('안녕'.encode('utf-8')))")"
write cjk_hangul_longer     "$(/usr/bin/python3 -c "print(repr('안녕하세요 void'.encode('utf-8')))")"
write cjk_hanzi             "$(/usr/bin/python3 -c "print(repr('你好世界'.encode('utf-8')))")"
write cjk_kana              "$(/usr/bin/python3 -c "print(repr('こんにちはカタカナ'.encode('utf-8')))")"
write cjk_mix_ascii         "$(/usr/bin/python3 -c "print(repr('abc가나다xyz'.encode('utf-8')))")"
write cjk_reset_and_cjk     "$(/usr/bin/python3 -c "print(repr(b'\\x1b[2J' + '가나다'.encode('utf-8')))")"
write cjk_nfd_decomposed    "$(/usr/bin/python3 -c "print(repr('\u1100\u1161'.encode('utf-8')))")"
write cjk_fullwidth_ascii   "$(/usr/bin/python3 -c "print(repr('ＡＢＣ'.encode('utf-8')))")"
write cjk_compat            "$(/usr/bin/python3 -c "print(repr('㈀㈁'.encode('utf-8')))")"
write cjk_right_edge        "$(/usr/bin/python3 -c "print(repr(b'A'*79 + '가'.encode('utf-8')))")"

# ── Emoji SMP (VP-08) (10) ──
write emoji_grin            "$(/usr/bin/python3 -c "print(repr('Hi 😀 X'.encode('utf-8')))")"
write emoji_heart           "$(/usr/bin/python3 -c "print(repr('love ❤ X'.encode('utf-8')))")"
write emoji_fire            "$(/usr/bin/python3 -c "print(repr('hot 🔥 X'.encode('utf-8')))")"
write emoji_rocket          "$(/usr/bin/python3 -c "print(repr('go 🚀 X'.encode('utf-8')))")"
write emoji_sparkle         "$(/usr/bin/python3 -c "print(repr('✨ shine'.encode('utf-8')))")"
write emoji_check           "$(/usr/bin/python3 -c "print(repr('✓ ok ✗ no'.encode('utf-8')))")"
write emoji_star            "$(/usr/bin/python3 -c "print(repr('rate ⭐⭐⭐'.encode('utf-8')))")"
write emoji_mixed_text      "$(/usr/bin/python3 -c "print(repr('🚀 launch 🔥 fire 🎉 party'.encode('utf-8')))")"
write emoji_wide_pictograph "$(/usr/bin/python3 -c "print(repr('🌀🌈🌊'.encode('utf-8')))")"
write emoji_tui_banner      "$(/usr/bin/python3 -c "print(repr('╭─ 🚀 Claude ─╮'.encode('utf-8')))")"

# ── Box drawing (10) ──
write box_horiz_line        "$(/usr/bin/python3 -c "print(repr(('─'*10).encode('utf-8')))")"
write box_vert_line         "$(/usr/bin/python3 -c "print(repr(('│\\n'*3).encode('utf-8')))")"
write box_corner_tl         "$(/usr/bin/python3 -c "print(repr('┌───┐'.encode('utf-8')))")"
write box_corner_bl         "$(/usr/bin/python3 -c "print(repr('└───┘'.encode('utf-8')))")"
write box_frame_small       "$(/usr/bin/python3 -c "print(repr('┌─┐\\r\\n│x│\\r\\n└─┘'.encode('utf-8')))")"
write box_double_horiz      "$(/usr/bin/python3 -c "print(repr(('═'*10).encode('utf-8')))")"
write box_heavy_horiz       "$(/usr/bin/python3 -c "print(repr(('━'*10).encode('utf-8')))")"
write box_rounded_tl        "$(/usr/bin/python3 -c "print(repr('╭───╮'.encode('utf-8')))")"
write box_cross             "$(/usr/bin/python3 -c "print(repr('┼─┼─┼'.encode('utf-8')))")"
write box_shade             "$(/usr/bin/python3 -c "print(repr('░▒▓█'.encode('utf-8')))")"

# ── TUI patterns (10) ──
write tui_spinner_dots      "$(/usr/bin/python3 -c "print(repr('⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'.encode('utf-8')))")"
write tui_progress_bar      "b'[' + b'#'*20 + b'-'*10 + b'] 66%'"
write tui_progress_ansi     "b'\\x1b[32m[' + b'#'*20 + b'\\x1b[37m-'*10 + b'\\x1b[0m]'"
write tui_cursor_hide_show  "b'\\x1b[?25lHIDDEN\\x1b[?25hSHOWN'"
write tui_alt_screen_on     "b'\\x1b[?1049hA'"
write tui_alt_screen_off    "b'\\x1b[?1049hA\\x1b[?1049lB'"
write tui_bracketed_paste   "b'\\x1b[200~pasted\\x1b[201~done'"
write tui_mouse_on          "b'\\x1b[?1000hclick\\x1b[?1000l'"
write tui_redraw            "b'\\x1b[2J\\x1b[HNEW'"
write tui_cl_banner         "$(/usr/bin/python3 -c "print(repr('\x1b[1;36m╭── 🤖 Claude ──╮\x1b[0m'.encode('utf-8')))")"

# ── Edge cases (10) ──
write edge_nul_byte         "b'A\\x00B'"
write edge_invalid_utf8     "b'A\\xffB'"
write edge_partial_utf8_1   "b'\\xe0'"
write edge_partial_utf8_2   "b'\\xe0\\xa0'"
write edge_long_line        "$(/usr/bin/python3 -c "print(repr(b'a' * 200))")"
write edge_ris_reset        "b'\\x1b[1;31;44mX\\x1bcY'"
write edge_sgr_many_params  "b'\\x1b[1;2;3;4;5;31;44mY\\x1b[0mN'"
write edge_decsc_decrc      "b'ABC\\x1b7\\x1b[5;10HX\\x1b8Y'"
write edge_osc_title        "b'\\x1b]0;title\\x07NEXT'"
write edge_csi_empty_params "b'\\x1b[;HX'"

echo "[gen] wrote 100 scenarios → $DIR"
ls "$DIR"/*.in | wc -l | awk '{print "[gen] .in count:", $1}'
