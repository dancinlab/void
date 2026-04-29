#!/bin/sh
# void-session-replay — read PersistRing files + dump recovered PTY bytes
# to stdout. P7 Phase B1 byte-side recovery without auto-restore.
#
# Usage:
#   void-session-replay --list        # enumerate ring files in ~/.void/sessions
#   void-session-replay --latest      # dump most recent ring's recovered bytes
#   void-session-replay --all         # dump every ring
#   void-session-replay <path>        # dump specific ring file
#
# Why this exists:
#   void's mmap'd PersistRing (src/termio/PersistRing.zig) writes per-Termio
#   PTY byte streams to ~/.void/sessions/by-pid/<pid>/<addr>.ring whenever
#   `persist-bytes-mmap = true` config is set. After void crash or macOS
#   panic, those rings still hold the most recent ≤4MB of each surface's
#   PTY output — but Phase B2 auto-restore (replay into freshly-spawned
#   surface during AppKit window restoration) is not yet implemented:
#   it requires plumbing a stable surface UUID through the Swift→Zig C
#   ABI boundary (deferred to a separate phase).
#
#   Until then, this tool gives the user direct read access to those
#   recovered bytes. Pipe to `less -R`, `cat`, or save to a file. The
#   bytes are genuinely preserved with bounds documented in the design:
#     - scenario A (void crash, mac up):  < 16KB loss
#     - scenario B (mac crash/reboot):    ≤ 1s loss (msync 1s cadence)
#
# Ring file format (must match src/termio/PersistRing.zig):
#   bytes 0..3   magic 0x52455650 ("PVER" little-endian)
#   bytes 4..7   padding
#   bytes 8..15  write_offset (u64 LE, monotonic since ring open)
#   bytes 16..23 generation (u64 LE, ++ on each wraparound)
#   bytes 24..31 reserved
#   bytes 32..   payload ring (4MB default)
#
# To replay newest-cap-bytes for write_offset W and capacity C:
#   if W < C:  payload[0..W] is the entire stream, in order.
#   else:      ring wrapped — phys = W mod C
#              payload[phys..C] then payload[0..phys]   = oldest→newest

set -e

SESS_ROOT="${HOME}/.void/sessions/by-pid"
HEADER_SIZE=32
DEFAULT_CAP=$((4 * 1024 * 1024))

usage() {
    cat >&2 <<EOF
usage: void-session-replay <--list|--latest|--all|<path>>
  --list           enumerate ring files in $SESS_ROOT
  --latest         dump most recently modified ring's recovered bytes
  --all            dump every ring (header to stderr, payload to stdout)
  <path>           dump bytes of one specific ring file
EOF
}

# Read u64 little-endian from file at offset, output as decimal.
read_u64_le() {
    file="$1"
    off="$2"
    # Use Python which is reliably available on macOS for portable u64.
    /usr/bin/python3 -c "
import sys, struct
with open('$file', 'rb') as f:
    f.seek($off)
    print(struct.unpack('<Q', f.read(8))[0])
"
}

# Validate magic at start of file.
validate_magic() {
    file="$1"
    # Read first 4 bytes, check for "PVER" (0x50 0x56 0x45 0x52)
    magic_hex=$(head -c 4 "$file" 2>/dev/null | xxd -p)
    [ "$magic_hex" = "50564552" ]
}

# List all ring files sorted by mtime (newest first).
list_rings() {
    if [ ! -d "$SESS_ROOT" ]; then
        echo "(no $SESS_ROOT — persist-bytes-mmap not enabled or no void session has run)" >&2
        return 0
    fi
    # macOS find has no -printf; use stat per-file.
    find "$SESS_ROOT" -type f -name '*.ring' 2>/dev/null | while read -r r; do
        mt=$(stat -f '%m' "$r" 2>/dev/null)
        echo "$mt $r"
    done | sort -rn | sed 's/^[0-9]* //'
}

# Dump payload bytes oldest→newest for a ring file.
dump_replay() {
    file="$1"
    if [ ! -f "$file" ]; then
        echo "[error] $file: not a regular file" >&2
        return 1
    fi
    if ! validate_magic "$file"; then
        echo "[invalid] $file: magic 'PVER' not found (not a PersistRing)" >&2
        return 1
    fi

    write_offset=$(read_u64_le "$file" 8)
    generation=$(read_u64_le "$file" 16)
    file_size=$(stat -f '%z' "$file")
    cap=$((file_size - HEADER_SIZE))
    if [ "$write_offset" -lt "$cap" ]; then
        have="$write_offset"
    else
        have="$cap"
    fi

    {
        echo "[ring] $file"
        echo "       write_offset=$write_offset generation=$generation cap=$cap have=$have"
    } >&2

    if [ "$have" -eq 0 ]; then
        return 0
    fi

    if [ "$write_offset" -lt "$cap" ]; then
        # No wrap: payload[0..write_offset]
        dd if="$file" bs=1 skip="$HEADER_SIZE" count="$have" 2>/dev/null
    else
        # Wrapped: phys = write_offset mod cap; output [phys..cap] then [0..phys]
        phys=$((write_offset % cap))
        first_len=$((cap - phys))
        # First segment: payload[phys..cap]
        dd if="$file" bs=1 skip=$((HEADER_SIZE + phys)) count="$first_len" 2>/dev/null
        # Second segment: payload[0..phys]
        if [ "$phys" -gt 0 ]; then
            dd if="$file" bs=1 skip="$HEADER_SIZE" count="$phys" 2>/dev/null
        fi
    fi
}

# ---------- main ----------

if [ "$#" -lt 1 ]; then
    usage
    exit 2
fi

mode="$1"

case "$mode" in
    --help|-h)
        usage
        exit 0
        ;;
    --list)
        if [ ! -d "$SESS_ROOT" ]; then
            echo "no ring files under $SESS_ROOT" >&2
            echo "(persist-bytes-mmap config not enabled, or no void session has run yet)" >&2
            exit 0
        fi
        listed=0
        for r in $(list_rings); do
            mt=$(stat -f '%m' "$r" 2>/dev/null)
            if validate_magic "$r"; then
                wo=$(read_u64_le "$r" 8)
                echo "$r  mtime=$mt  write_offset=$wo  valid=true"
            else
                echo "$r  mtime=$mt  valid=false"
            fi
            listed=$((listed + 1))
        done
        if [ "$listed" -eq 0 ]; then
            echo "no ring files under $SESS_ROOT" >&2
        fi
        exit 0
        ;;
    --latest)
        rings=$(list_rings)
        if [ -z "$rings" ]; then
            echo "no ring files under $SESS_ROOT" >&2
            exit 1
        fi
        # First line is newest (sorted -rn by mtime).
        latest=$(echo "$rings" | head -n 1)
        dump_replay "$latest"
        exit 0
        ;;
    --all)
        rings=$(list_rings)
        if [ -z "$rings" ]; then
            echo "no ring files under $SESS_ROOT" >&2
            exit 1
        fi
        for r in $rings; do
            dump_replay "$r"
        done
        exit 0
        ;;
    -*)
        echo "unknown flag: $mode" >&2
        usage
        exit 2
        ;;
    *)
        # Specific path
        dump_replay "$mode"
        exit 0
        ;;
esac
