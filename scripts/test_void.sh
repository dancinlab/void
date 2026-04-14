#!/usr/bin/env bash
# Background-runnable self-test harness for void_term.
#
# Flow:
#   1. Rebuild /tmp/void_term if source newer (or --force).
#   2. Run VOID_TEST=1 /tmp/void_term with timeout → /tmp/void_test.log
#   3. Parse log: count PASS/FAIL, detect premature exit, print summary.
#   4. Exit 0 only when PASS >= expected AND no FAIL lines AND final
#      "ALL TESTS PASS" or "passed" summary present.
#
# No GUI required — self_test path returns before AppKit init.
# Safe to run from Claude Code CLI in background.

set -u
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BIN="${BIN:-/tmp/void_term}"
LOG="${LOG:-/tmp/void_test.log}"
EXPECTED_MIN="${EXPECTED_MIN:-25}"    # total T1..T25 in self_test
TIMEOUT_SEC="${TIMEOUT_SEC:-30}"
RC=0

log() { printf '[harness] %s\n' "$*"; }
die() { printf '[harness] FATAL: %s\n' "$*" >&2; exit 2; }

# ── 1. Build (if needed) ───────────────────────────────────────────
# --no-rebuild: caller (e.g. build_void.sh) supplies BIN; skip build step.
NO_REBUILD=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --no-rebuild) NO_REBUILD=1 ;;
    --force)      FORCE=1 ;;
  esac
done

need_build=0
if [[ $FORCE -eq 1 ]]; then need_build=1; fi
if [[ ! -x "$BIN" ]]; then need_build=1; fi
if [[ $need_build -eq 0 && -x "$BIN" ]]; then
  for src in "$ROOT/src/void_main.hexa" \
             "$ROOT/src/sys_pty.c" \
             "$ROOT/src/sys_appkit.m" \
             "$ROOT/src/prompt_parser.hexa" \
             "$ROOT/src/history_ring.hexa" \
             "$ROOT/src/cmd_parser.hexa" \
             "$ROOT/src/state_ssot.hexa" \
             "$ROOT/src/builtin_cmds.hexa"; do
    [[ -f "$src" && "$src" -nt "$BIN" ]] && { need_build=1; break; }
  done
fi

if [[ $NO_REBUILD -eq 1 ]]; then
  [[ -x "$BIN" ]] || { log "FAIL: --no-rebuild but $BIN missing"; exit 5; }
  log "binary supplied: $BIN (no-rebuild)"
elif [[ $need_build -eq 1 ]]; then
  log "rebuilding $BIN (via build_void.sh, which will re-invoke us)…"
  "$ROOT/scripts/build_void.sh" > /tmp/void_build.log 2>&1 || {
    log "build FAILED — see /tmp/void_build.log (last 15 lines):"
    tail -15 /tmp/void_build.log
    exit 3
  }
  log "build OK → $(ls -la "$BIN" | awk '{print $5,$9}')"
else
  log "binary up-to-date: $BIN"
fi

# ── 2. Run self-test (background-safe, with timeout) ───────────────
log "running VOID_TEST=1 $BIN (timeout ${TIMEOUT_SEC}s) …"
rm -f "$LOG"
( VOID_TEST=1 "$BIN" > "$LOG" 2>&1 & echo $! > /tmp/void_test.pid ) &
TEST_PGID=$!

# Wait with timeout
waited=0
PID="$(cat /tmp/void_test.pid 2>/dev/null || echo 0)"
while [[ $waited -lt $TIMEOUT_SEC ]]; do
  if ! kill -0 "$PID" 2>/dev/null; then break; fi
  sleep 1
  waited=$((waited + 1))
done
if kill -0 "$PID" 2>/dev/null; then
  log "TIMEOUT after ${TIMEOUT_SEC}s — killing PID $PID"
  kill -9 "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
  RC=124
fi
wait "$TEST_PGID" 2>/dev/null

# ── 3. Parse log ────────────────────────────────────────────────────
if [[ ! -s "$LOG" ]]; then
  log "FAIL: no output at all (binary silent) — check $LOG + $BIN"
  exit 4
fi

pass=$(grep -c 'T[0-9]\+ PASS' "$LOG" || true)
fail=$(grep -c 'T[0-9]\+ FAIL' "$LOG" || true)
start=$(grep -c 'SELF-TEST START' "$LOG" || true)
done_line=$(grep -c 'ALL TESTS PASS\|passed$' "$LOG" || true)

log "────────────── summary ──────────────"
log "  start marker : $start  (expect 1)"
log "  PASS count   : $pass   (expect ≥ $EXPECTED_MIN)"
log "  FAIL count   : $fail   (expect 0)"
log "  done marker  : $done_line  (expect 1)"
log "  log file     : $LOG  ($(wc -l < "$LOG" | tr -d ' ') lines)"
log "────────────────────────────────────"

# ── 4. Diagnose + exit ─────────────────────────────────────────────
if [[ $fail -gt 0 ]]; then
  log "FAIL lines:"
  grep 'T[0-9]\+ FAIL' "$LOG" | sed 's/^/  /'
  RC=1
fi
if [[ $pass -lt $EXPECTED_MIN ]]; then
  log "PREMATURE-EXIT: only $pass/$EXPECTED_MIN tests produced PASS output"
  log "  last 3 lines of log:"
  tail -3 "$LOG" | sed 's/^/    /'
  last_passed=$(grep 'T[0-9]\+ PASS' "$LOG" | tail -1 | grep -oE 'T[0-9]+' | head -1)
  log "  last test to PASS: ${last_passed:-none} — execution halted afterwards"
  RC=${RC:-1}
  [[ $RC -eq 0 ]] && RC=1
fi
if [[ $done_line -eq 0 ]]; then
  log "MISSING: final summary line ('ALL TESTS PASS' / 'passed')"
  [[ $RC -eq 0 ]] && RC=1
fi

if [[ $RC -eq 0 ]]; then
  log "✓ ALL GREEN — $pass/$EXPECTED_MIN tests passed"
else
  log "✗ exit=$RC — see $LOG for details"
fi
exit $RC
