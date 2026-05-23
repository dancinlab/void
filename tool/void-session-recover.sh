#!/bin/sh
# void-session-recover — scan PersistRing files and produce a human-readable
# inventory of last cwd hint per ring. Companion to void-session-replay.sh
# (that dumps one ring, this picks which one out of 100+ post-crash).
#
# Usage:
#   void-session-recover.sh                # scan ~/.void/sessions/by-uuid
#   void-session-recover.sh <directory>    # scan custom dir of .ring files
#
# Output (tab-separated, header row first, sorted by mtime desc):
#   UUID   bytes   last_mtime (YYYY-MM-DD)   cwd_hint
#
# Cwd-hint heuristic: replay → strip control bytes → strip ANSI CSI → grep
# absolute (/Users|home|tmp|opt|private|var) or ~/ paths → pick the LAST
# match that test -d says exists; else last raw match; else "?".
#
# Ring file format (src/termio/PersistRing.zig):
#   bytes 0..3   magic "PVER" LE  ·  bytes 8..15  write_offset u64 LE

set -e

DEFAULT_DIR="${HOME}/.void/sessions/by-uuid"

usage() {
    cat >&2 <<EOF
usage: void-session-recover.sh [<directory>]
  scans <directory> (default: $DEFAULT_DIR) for *.ring files and prints a
  tab-separated inventory with the last cwd hint extracted from each ring's
  recovered PTY bytes. Sorted by mtime (newest first).
EOF
}

# Read u64 little-endian from $1 at byte offset $2 (decimal output).
read_u64_le() {
    /usr/bin/python3 -c "
import struct
with open('$1','rb') as f:
    f.seek($2); print(struct.unpack('<Q', f.read(8))[0])
"
}

# Check "PVER" magic at byte 0.
valid_magic() {
    [ "$(head -c 4 "$1" 2>/dev/null | xxd -p)" = "50564552" ]
}

# Print last plausible cwd extracted from a ring's replayed bytes.
extract_cwd_hint() {
    ring="$1"
    paths=$(
        "$REPLAY" "$ring" 2>/dev/null \
            | LC_ALL=C tr -d '\000-\010\013-\037' \
            | LC_ALL=C sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
            | LC_ALL=C grep -aoE '(/(Users|home|tmp|opt|private|var)/[A-Za-z0-9._/+-]+|~/[A-Za-z0-9._/+-]+)' \
            | tail -50
    )
    [ -z "$paths" ] && { echo "?"; return; }
    # Prefer last path that exists (expand leading ~ for test).
    last_existing=""
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        check="$p"
        case "$p" in ~*) check="${HOME}${p#~}" ;; esac
        [ -d "$check" ] && last_existing="$p"
    done <<INNER
$paths
INNER
    if [ -n "$last_existing" ]; then
        echo "$last_existing"
    else
        echo "$paths" | tail -n 1
    fi
}

# ---------- main ----------

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac

DIR="${1:-$DEFAULT_DIR}"
if [ ! -d "$DIR" ]; then
    echo "error: directory not found: $DIR" >&2
    exit 2
fi

# Locate companion replay script (same directory as this one).
SELF_DIR=$(dirname "$0")
REPLAY="$SELF_DIR/void-session-replay.sh"
if [ ! -x "$REPLAY" ]; then
    echo "error: void-session-replay.sh not found or not executable at $REPLAY" >&2
    exit 2
fi

# Header row.
printf 'UUID\tbytes\tlast_mtime\tcwd_hint\n'

# Gather "<mtime>\t<path>" lines, sort newest first.
find "$DIR" -type f -name '*.ring' 2>/dev/null | while read -r r; do
    mt=$(stat -f '%m' "$r" 2>/dev/null) || continue
    printf '%s\t%s\n' "$mt" "$r"
done | sort -rn | while IFS="$(printf '\t')" read -r mt path; do
    [ -z "$path" ] && continue
    if ! valid_magic "$path"; then
        echo "[skip] $path: bad magic (not a PersistRing)" >&2
        continue
    fi
    uuid=$(basename "$path" .ring)
    wo=$(read_u64_le "$path" 8)
    date_str=$(date -r "$mt" '+%Y-%m-%d' 2>/dev/null || echo '?')
    if [ "$wo" -eq 0 ]; then
        hint="empty"
    else
        hint=$(extract_cwd_hint "$path")
    fi
    printf '%s\t%s\t%s\t%s\n' "$uuid" "$wo" "$date_str" "$hint"
done
