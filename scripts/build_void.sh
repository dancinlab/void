#!/usr/bin/env bash
# One-shot builder for /tmp/void_term — patches known u_main gap in
# hexa-generated C, then links with clang + Cocoa/CoreText.
#
# HARNESS ENFORCEMENT:
#   - Links to a STAGING path (/tmp/void_term.stage).
#   - Runs VOID_TEST=1 against the staging binary via test_void.sh.
#   - Only promotes to /tmp/void_term if all 25 tests pass.
#   - On failure: deletes the staging binary AND removes any existing
#     /tmp/void_term so downstream callers can never run an untested
#     binary. The only way to produce /tmp/void_term is to pass tests.
#
# Background-safe, idempotent. Exits non-zero on any build/test failure.
# Set SKIP_TESTS=1 to bypass (e.g. CI bootstrap) — print a warning.

set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
HEXA="${HEXA:-${HEXA_LANG:-$HOME/Dev/hexa-lang}/hexa}"
HEXA_SELF="${HEXA_SELF:-${HEXA_LANG:-$HOME/Dev/hexa-lang}/self}"
FINAL="${OUT:-/tmp/void_term}"
STAGE="${FINAL}.stage"
OUT="$STAGE"
ARTIFACT="$ROOT/build/artifacts/void_term_new.c"
PATCHED="$ROOT/build/artifacts/void_term_new.patched.c"

mkdir -p "$ROOT/build/artifacts"

# ── B3: Transpile hash cache ────────────────────────────────────────
# Content-addressed cache at ~/.cache/void/transpile/<sha>.c.
# Hash = sha256(sorted(sha256 of each src/*.hexa) || sha256 of $HEXA).
# Env:
#   CACHE_DISABLE=1    → skip both read and write (CI / debugging).
#   FORCE_TRANSPILE=1  → skip read only (always overwrite cache).
# The hash includes the HEXA compiler binary so a hexa-lang upgrade
# invalidates every cached entry automatically.
VOID_CACHE_DIR="${VOID_CACHE_DIR:-$HOME/.cache/void/transpile}"
mkdir -p "$VOID_CACHE_DIR"

_void_hasher() {
  if command -v shasum       >/dev/null 2>&1; then shasum -a 256
  elif command -v sha256sum  >/dev/null 2>&1; then sha256sum
  else cat >/dev/null; echo "FAIL"; fi
}

compute_src_hash() {
  {
    for src in "$ROOT"/src/*.hexa; do
      [[ -f "$src" ]] && _void_hasher <"$src" | awk -v n="$(basename "$src")" '{print $1, n}'
    done | LC_ALL=C sort
    [[ -x "$HEXA" ]] && _void_hasher <"$HEXA" | awk '{print $1, "HEXA"}'
  } | _void_hasher | awk '{print $1}'
}

SRC_HASH=""
if [[ "${CACHE_DISABLE:-0}" != "1" ]]; then
  SRC_HASH="$(compute_src_hash 2>/dev/null || true)"
fi

# ── Transpile gate: skip hexa build if .c is newer than sources ────
# VB1: native `hexa build` is a 45-min worst case. Only re-transpile
# when any .hexa source is newer than the cached .c artifact.
#   FORCE_TRANSPILE=1  → always re-transpile (bypass mtime gate).
#   SKIP_TRANSPILE=1   → always skip re-transpile (ObjC/C-only edits).
#                        Requires a pre-existing $ARTIFACT; aborts otherwise.
need_transpile=0
skip_transpile_forced=0
if [[ "${SKIP_TRANSPILE:-0}" == "1" ]]; then
  if [[ ! -s "$ARTIFACT" ]]; then
    echo "[build] FAIL: SKIP_TRANSPILE=1 but no cached $ARTIFACT exists"
    exit 1
  fi
  skip_transpile_forced=1
else
  if [[ "${FORCE_TRANSPILE:-0}" == "1" ]]; then need_transpile=1; fi
  if [[ ! -s "$ARTIFACT" ]]; then need_transpile=1; fi
  if [[ $need_transpile -eq 0 ]]; then
    for src in "$ROOT"/src/*.hexa; do
      [[ -f "$src" && "$src" -nt "$ARTIFACT" ]] && { need_transpile=1; break; }
    done
  fi
fi

# ── B3: cache hit check (pre-transpile) ────────────────────────────
# If mtime gate wants a re-transpile but content is unchanged (e.g.
# whitespace-only edit, git checkout between matching branches, undo/
# redo to prior state), copy cached .c and skip the 45-min transpile.
if [[ $need_transpile -eq 1 && -n "$SRC_HASH" && "${FORCE_TRANSPILE:-0}" != "1" ]]; then
  CACHED_C="$VOID_CACHE_DIR/$SRC_HASH.c"
  if [[ -s "$CACHED_C" ]]; then
    echo "[build] transpile: cache hit (${SRC_HASH:0:12}) — copy cached .c → $ARTIFACT"
    cp "$CACHED_C" "$ARTIFACT"
    # touch so subsequent mtime-gate runs in this session treat it fresh.
    touch "$ARTIFACT"
    need_transpile=0
  fi
fi

if [[ $need_transpile -eq 1 ]]; then
  # hexa build writes the intermediate .c to build/artifacts/<stem>.c where
  # stem = basename of -o argument minus .hexa (self/main.hexa:552). So we
  # pass -o ending in `void_term_new` to get build/artifacts/void_term_new.c
  # — matching $ARTIFACT. Any prior -o like `.stage.stage1` yielded the
  # wrong .c path and the script then patched+linked STALE C from yesterday.
  echo "[build] transpile: hexa build $ROOT/src/void_main.hexa (may take minutes)"
  (cd "$ROOT" && "$HEXA" build src/void_main.hexa -o /tmp/void_term_new 2>/tmp/void_build_stage1.log) || {
    if [[ ! -s "$ARTIFACT" ]]; then
      echo "[build] FAIL: transpile did not produce $ARTIFACT"
      tail -30 /tmp/void_build_stage1.log
      exit 1
    fi
    echo "[build] stage1 linker failure ignored (we relink ourselves)"
  }
  # Sanity: confirm the fresh .c was produced AND is newer than sources.
  for src in "$ROOT"/src/*.hexa; do
    if [[ -f "$src" && "$src" -nt "$ARTIFACT" ]]; then
      echo "[build] FAIL: transpile did not refresh $ARTIFACT (still older than $src)"
      echo "        hexa-lang stem mismatch? expected build/artifacts/void_term_new.c"
      ls -la "$ARTIFACT" "$src"
      exit 1
    fi
  done
  # ── B3: populate cache with fresh .c ────────────────────────────
  if [[ -n "$SRC_HASH" && -s "$ARTIFACT" && "${CACHE_DISABLE:-0}" != "1" ]]; then
    cp "$ARTIFACT" "$VOID_CACHE_DIR/$SRC_HASH.c" 2>/dev/null \
      && echo "[build] transpile: cached .c → ${VOID_CACHE_DIR}/${SRC_HASH:0:12}.c"
  fi
elif [[ $skip_transpile_forced -eq 1 ]]; then
  echo "[build] transpile: forced skip via SKIP_TRANSPILE=1 (artifact: $ARTIFACT)"
else
  echo "[build] transpile: skip (artifact up-to-date: $ARTIFACT)"
fi

# Duplicate symbol patches: any symbol defined as `T` (global text) in
# sys_pty.o or sys_appkit.o AND defined as an FFI proxy in the hexa-
# generated .c must be prefixed `static` in the .c so both defs can
# coexist (the .c version is only used by hexa-internal call sites; the
# real impl lives in sys_pty.c / sys_appkit.m).
cp "$ARTIFACT" "$PATCHED"

TMPOBJ=/tmp/void_build_dupes
mkdir -p "$TMPOBJ"
clang -O0 -c -I "$HEXA_SELF" "$ROOT/src/sys_pty.c"    -o "$TMPOBJ/sys_pty.o"    2>/dev/null
clang -O0 -c -I "$HEXA_SELF" -ObjC "$ROOT/src/sys_appkit.m" -o "$TMPOBJ/sys_appkit.o" 2>/dev/null
# Collect global-text symbols from both .o files, strip leading underscore.
nm "$TMPOBJ/sys_pty.o" "$TMPOBJ/sys_appkit.o" 2>/dev/null \
  | awk '$2=="T" {sub(/^_/,"",$3); print $3}' \
  | sort -u > "$TMPOBJ/dupes.txt"
dupe_count=$(wc -l < "$TMPOBJ/dupes.txt" | tr -d ' ')
echo "[build] duplicate-candidate symbols from sys_pty/sys_appkit: $dupe_count"

/usr/bin/python3 - "$PATCHED" "$TMPOBJ/dupes.txt" <<'PY'
import sys, re
path, dupes_path = sys.argv[1], sys.argv[2]
with open(dupes_path) as f:
    dupes = {ln.strip() for ln in f if ln.strip()}
with open(path) as f:
    lines = f.readlines()
# Forward-decl line:  "HexaVal sym(...);"  or  "long sym(void);"
# Definition line:    "HexaVal sym(...) {" or  "long sym(...) {"
pat = re.compile(r'^((?:HexaVal|long|int|void)\s+)(\w+)(\s*\()')
patched = 0
for i, ln in enumerate(lines):
    m = pat.match(ln)
    if m and m.group(2) in dupes and not ln.lstrip().startswith('static '):
        lines[i] = 'static ' + ln
        patched += 1
with open(path, 'w') as f:
    f.writelines(lines)
print(f'[build]   lines prefixed `static`: {patched}')
PY

# Inject u_main() call at end of main() if missing.
if ! grep -q 'u_main()' "$PATCHED" 2>/dev/null || [[ $(grep -c 'u_main()' "$PATCHED") -lt 2 ]]; then
  # The last "    return 0;\n}" in the file belongs to main().
  # Replace it with u_main() call.
  /usr/bin/python3 - "$PATCHED" <<'PY'
import sys, re
p = sys.argv[1]
with open(p) as f:
    txt = f.read()
# Find last "    return 0;\n}" (main's closing) and splice.
marker = "    return 0;\n}\n"
idx = txt.rfind(marker)
if idx < 0:
    sys.exit("could not find main's return 0 marker")
replacement = (
    "    HexaVal __r_main = u_main();\n"
    "    return (__r_main.tag == TAG_INT) ? (int)__r_main.i : 0;\n"
    "}\n"
)
txt = txt[:idx] + replacement + txt[idx+len(marker):]
with open(p, 'w') as f:
    f.write(txt)
PY
  echo "[build] injected u_main() call into main()"
fi

echo "[build] clang link → $STAGE (staging)"
clang -O2 -Wno-trigraphs -fbracket-depth=512 \
  -I "$HEXA_SELF" \
  "$PATCHED" \
  "$ROOT/src/sys_pty.c" \
  "$ROOT/src/sys_appkit.m" \
  "$ROOT/src/paste_util.c" \
  -framework Cocoa -framework CoreText \
  -o "$STAGE" 2>&1

echo "[build] stage OK: $(ls -la "$STAGE" | awk '{print $5,$9}')"

# ── C-level test gate: paste_test (bracketed-paste helpers) ────────
# Runs before the hexa self_test so a broken paste helper fails fast.
PASTE_TEST=/tmp/void_paste_test
echo "[build] compile + run paste_test …"
clang -O2 -I "$HEXA_SELF" \
  "$ROOT/src/paste_util.c" "$ROOT/tests/paste_test.c" \
  -o "$PASTE_TEST" 2>&1
if ! "$PASTE_TEST"; then
  echo "[build] ✗ paste_test rejected — removing staging"
  rm -f "$STAGE"
  exit 6
fi

# ── HARNESS ENFORCEMENT ────────────────────────────────────────────
# Nothing downstream may use /tmp/void_term without passing tests.
# We delete $FINAL up-front so a stale binary can't masquerade as
# "tested" on test failure. Then: test → promote, or abort.
rm -f "$FINAL"

if [[ "${SKIP_TESTS:-0}" == "1" ]]; then
  echo "[build] ⚠️  SKIP_TESTS=1 — promoting $STAGE → $FINAL WITHOUT tests"
  mv "$STAGE" "$FINAL"
  exit 0
fi

echo "[build] harness: running self-test against staging binary …"
BIN="$STAGE" LOG=/tmp/void_test_stage.log EXPECTED_MIN=28 \
  "$ROOT/scripts/test_void.sh" --no-rebuild
test_rc=$?
if [[ $test_rc -ne 0 ]]; then
  echo "[build] ✗ HARNESS REJECTED staging binary (exit=$test_rc)"
  echo "[build]   staging removed — no /tmp/void_term produced"
  rm -f "$STAGE"
  exit $test_rc
fi

# Headless renderer regressions — run the staging binary through every
# tests/headless/*.in scenario. Each compares the post-feed grid dump
# to a committed *.grid golden. Skipped when SKIP_HEADLESS=1 (e.g.
# during a scenario update: run test_headless.sh manually with
# UPDATE_GOLDEN=1 and commit).
if [[ "${SKIP_HEADLESS:-0}" != "1" ]] && [[ -d "$ROOT/tests/headless" ]]; then
  echo "[build] harness: running headless scenarios …"
  BIN="$STAGE" "$ROOT/scripts/test_headless.sh"
  headless_rc=$?
  if [[ $headless_rc -ne 0 ]]; then
    echo "[build] ✗ HEADLESS REJECTED staging binary (exit=$headless_rc)"
    rm -f "$STAGE"
    exit $headless_rc
  fi
fi

mv "$STAGE" "$FINAL"
echo "[build] ✓ harness-approved: $(ls -la "$FINAL" | awk '{print $5,$9}')"
