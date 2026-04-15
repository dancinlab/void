#!/usr/bin/env bash
# Background-safe renderer regression harness for void_term.
#
# Two scenario modes driven by tests/headless/<name>.opts:
#   (A) feed mode (default) — replay VOID_HEADLESS_FEED=<name>.in bytes
#       through the hexa VT parser with no NSApp. Compares <name>.grid.
#   (B) offscreen mode — OFFSCREEN=1 in .opts. Full AppKit init with
#       window at (-99999,-99999) alpha=0. Optional SPAWN=<cmd> forks
#       a real PTY, ACTION=<id> dispatches a Cmd shortcut (profile1..9,
#       grid, stacked, new_tab, close_tab). Compares <name>.grid AND
#       <name>.png (shasum).
#
# UPDATE_GOLDEN=1 regenerates goldens. TMO=<sec> sets the kill timeout.

set -u
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BIN="${BIN:-/tmp/void_term}"
SDIR="${SDIR:-$ROOT/tests/headless}"
TMO="${TMO:-10}"
UPDATE="${UPDATE_GOLDEN:-0}"
TOTAL=0; PASS=0; FAIL=0

log() { printf '[headless] %s\n' "$*"; }
die() { printf '[headless] FATAL: %s\n' "$*" >&2; exit 2; }

[[ -x "$BIN" ]] || die "binary missing: $BIN"
[[ -d "$SDIR" ]] || die "scenario dir missing: $SDIR"

FAKE_HOME="${FAKE_HOME:-/tmp/void_headless_home}"
mkdir -p "$FAKE_HOME/.void"

run_one() {
    local name="$1"
    local in_path="$SDIR/$name.in"
    local opt_path="$SDIR/$name.opts"
    local golden="$SDIR/$name.grid"
    local png_golden="$SDIR/$name.png.sha"
    local out="/tmp/void_headless_${name}.grid"
    local png_out="/tmp/void_headless_${name}.png"
    local err="/tmp/void_headless_${name}.log"
    TOTAL=$((TOTAL+1))

    local rows=24 cols=80 max_ticks=30 offscreen=0 spawn="" action="" use_real_home=0
    if [[ -f "$opt_path" ]]; then
        while IFS='=' read -r k v; do
            [[ -z "${k// }" || "$k" == \#* ]] && continue
            case "$k" in
              ROWS)      rows="$v" ;;
              COLS)      cols="$v" ;;
              MAX_TICKS) max_ticks="$v" ;;
              OFFSCREEN) offscreen="$v" ;;
              SPAWN)     spawn="$v"; use_real_home=1 ;;
              ACTION)    action="$v" ;;
              REAL_HOME) use_real_home="$v" ;;
            esac
        done < "$opt_path"
    fi
    # Feed mode sanity — no SPAWN and no ACTION → needs .in file.
    if [[ -z "$spawn" && -z "$action" && ! -f "$in_path" ]]; then
        log "MISS  $name — no .in file and no SPAWN/ACTION"
        FAIL=$((FAIL+1)); return
    fi
    rm -f "$out" "$err" "$png_out" "$FAKE_HOME/.void/session.json"

    local home_val="$FAKE_HOME"
    [[ "$use_real_home" == "1" ]] && home_val="$HOME"

    (
      export HOME="$home_val"
      export VOID_HEADLESS=1
      export VOID_HEADLESS_DUMP="$out"
      export VOID_HEADLESS_ROWS="$rows"
      export VOID_HEADLESS_COLS="$cols"
      export VOID_HEADLESS_MAX_TICKS="$max_ticks"
      [[ -f "$in_path" ]] && export VOID_HEADLESS_FEED="$in_path"
      [[ -n "$spawn" ]]  && export VOID_HEADLESS_SPAWN="$spawn"
      [[ -n "$action" ]] && export VOID_HEADLESS_ACTION="$action"
      if [[ "$offscreen" == "1" ]]; then
          export VOID_HEADLESS_OFFSCREEN=1
          export VOID_HEADLESS_SNAPSHOT="$png_out"
      fi
      "$BIN" >/dev/null 2>"$err" &
      vpid=$!
      waited=0
      while kill -0 "$vpid" 2>/dev/null; do
          sleep 1
          waited=$((waited+1))
          [[ $waited -ge $TMO ]] && { kill -9 "$vpid" 2>/dev/null; break; }
      done
      wait "$vpid" 2>/dev/null
    )

    if [[ ! -s "$out" ]]; then
        log "FAIL  $name — empty dump (stderr tail:)"
        tail -5 "$err" | sed 's/^/    /'
        FAIL=$((FAIL+1)); return
    fi

    if [[ "$UPDATE" == "1" ]]; then
        cp "$out" "$golden"
        local msg="WROTE $name → $(basename "$golden") ($(wc -c < "$golden" | tr -d ' ')B)"
        if [[ "$offscreen" == "1" && -s "$png_out" ]]; then
            shasum -a 256 "$png_out" | awk '{print $1}' > "$png_golden"
            msg="$msg + PNG sha"
        fi
        log "$msg"
        PASS=$((PASS+1)); return
    fi
    if [[ ! -f "$golden" ]]; then
        log "MISS  $name — no golden; rerun with UPDATE_GOLDEN=1"
        FAIL=$((FAIL+1)); return
    fi
    local grid_ok=1 png_ok=1 png_expected="" png_actual=""
    if ! diff -q "$golden" "$out" >/dev/null 2>&1; then
        grid_ok=0
    fi
    if [[ "$offscreen" == "1" && -f "$png_golden" ]]; then
        png_expected="$(cat "$png_golden")"
        png_actual="$(shasum -a 256 "$png_out" 2>/dev/null | awk '{print $1}')"
        [[ "$png_expected" != "$png_actual" ]] && png_ok=0
    fi
    if [[ $grid_ok -eq 1 && $png_ok -eq 1 ]]; then
        log "PASS  $name"
        PASS=$((PASS+1))
    else
        if [[ $grid_ok -eq 0 ]]; then
            log "FAIL  $name — grid diff:"
            diff -u "$golden" "$out" | head -30 | sed 's/^/    /'
        fi
        if [[ $png_ok -eq 0 ]]; then
            log "FAIL  $name — PNG sha mismatch: expected=$png_expected actual=$png_actual"
        fi
        FAIL=$((FAIL+1))
    fi
}

if [[ $# -eq 0 ]]; then
    # Discover by .in OR .opts (BSD sed: use -E for |)
    names=$(ls "$SDIR" 2>/dev/null | sed -E -n 's/\.(in|opts)$//p' | sort -u)
    for name in $names; do run_one "$name"; done
    [[ -z "$names" ]] && { log "no scenarios in $SDIR"; exit 0; }
else
    for name in "$@"; do run_one "$name"; done
fi

log "────────────── headless summary ──────────────"
log "  total: $TOTAL  PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]]
