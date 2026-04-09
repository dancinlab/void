#!/bin/bash
# void release packaging — builds tarball after build.sh passes.
# Location note: lives under src/scripts/ to satisfy HEXA-FIRST hook;
# root wrapper scripts/release.sh forwards here.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <version>   (e.g. 0.5.0)" >&2
  exit 1
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: version must match ^[0-9]+\.[0-9]+\.[0-9]+$ (got: $VERSION)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
[ -z "$ROOT" ] && ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

echo "[release] version=$VERSION"
echo "[release] running build..."
if ! bash "$ROOT/src/scripts/build.sh"; then
  echo "[release] ABORT: build failed" >&2
  exit 1
fi

mkdir -p dist
OUT="dist/void-${VERSION}.tar.gz"

INCLUDE=(src)
[ -f README.md ]  && INCLUDE+=(README.md)
[ -f LICENSE ]    && INCLUDE+=(LICENSE)
[ -f CLAUDE.md ]  && INCLUDE+=(CLAUDE.md)
[ -f CHANGELOG.md ] && INCLUDE+=(CHANGELOG.md)
[ -f RELEASE.md ] && INCLUDE+=(RELEASE.md)

echo "[release] packaging: ${INCLUDE[*]}"
tar --exclude='.*' --exclude='dist' -czf "$OUT" "${INCLUDE[@]}"

SIZE=$(wc -c < "$OUT" | tr -d ' ')
echo "[release] wrote $OUT ($SIZE bytes)"
echo
echo "Next steps (not executed automatically):"
echo "  git tag v${VERSION}"
echo "  git push --tags"
echo
echo "[release] OK"
