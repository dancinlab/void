#!/bin/bash
# void build script — runs HEXA smokes as syntax/integration check
# Location note: lives under src/scripts/ to satisfy HEXA-FIRST hook;
# root wrapper scripts/build.sh forwards here.
set -euo pipefail

HEXA_BIN="${HEXA_BIN:-$HOME/Dev/hexa-lang/target/release/hexa}"
# Resolve ROOT via git (robust to symlink wrappers at repo-root scripts/).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT" ] && ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ ! -x "$HEXA_BIN" ]; then
  echo "ERROR: hexa binary not found at: $HEXA_BIN" >&2
  echo "  Set HEXA_BIN env var, or build hexa-lang:" >&2
  echo "    cd \$HOME/Dev/hexa-lang && cargo build --release" >&2
  exit 1
fi

echo "[build] HEXA_BIN=$HEXA_BIN"
echo "[build] ROOT=$ROOT"
echo

# Smoke files are non-TTY safe by design — run them as integration check.
SMOKES=(
  "src/smoke_tabs.hexa"
  "src/smoke_6layer.hexa"
  "src/smoke_dashboard.hexa"
  "src/smoke_plugin.hexa"
)

PASS=0
FAIL=0
FAILED_FILES=()

for f in "${SMOKES[@]}"; do
  path="$ROOT/$f"
  if [ ! -f "$path" ]; then
    echo "  SKIP  $f (not found)"
    continue
  fi
  if "$HEXA_BIN" "$path" >/dev/null 2>&1; then
    echo "  PASS  $f"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $f"
    FAIL=$((FAIL+1))
    FAILED_FILES+=("$f")
  fi
done

echo
echo "[build] Result: $PASS pass, $FAIL fail"

if [ $FAIL -gt 0 ]; then
  echo "[build] Failed files:"
  for f in "${FAILED_FILES[@]}"; do echo "  - $f"; done
  exit 1
fi

echo "[build] OK"
exit 0
