#!/bin/sh
# test-void-session-recover — edge-case harness for void-session-recover.sh.
#
# Builds synthetic PersistRing files matching src/termio/PersistRing.zig's
# 32-byte header layout, then asserts that void-session-recover.sh emits
# the expected cwd_hint per scenario.
#
# Header layout (PersistRing.zig):
#   bytes 0..3   magic 0x52455650 ("PVER" LE)
#   bytes 4..7   padding
#   bytes 8..15  write_offset (u64 LE)
#   bytes 16..23 generation (u64 LE)
#   bytes 24..31 last_msync_ns (u64 LE)
#   bytes 32..   payload ring (cap bytes)
#
# recover.sh output (tab-separated, header row first):
#   UUID   bytes   last_mtime   cwd_hint
#
# Path regex inside recover.sh:
#   (/(Users|home|tmp|opt|private|var)/[A-Za-z0-9._/+-]+|~/[A-Za-z0-9._/+-]+)
# Key implications encoded in test expectations:
#   - bare /tmp does NOT match (regex requires at least one path-char after).
#     Use /private/tmp instead for existing-path coverage on macOS.
#   - charset excludes 0x80-0xff so UTF-8 path matches truncate at the
#     first non-ASCII byte.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
RECOVER="$SELF_DIR/void-session-recover.sh"
REPLAY="$SELF_DIR/void-session-replay.sh"

if [ ! -x "$RECOVER" ]; then
    echo "fatal: recover script not executable at $RECOVER" >&2
    exit 2
fi
if [ ! -x "$REPLAY" ]; then
    echo "fatal: replay script not executable at $REPLAY" >&2
    exit 2
fi

WORKDIR=$(mktemp -d -t void-recover-test.XXXXXX)
RING_DIR="$WORKDIR/by-uuid"
mkdir -p "$RING_DIR"

UTF8_DIR="/tmp/void-recover-utf8-한글-테스트"

cleanup() {
    rm -rf "$WORKDIR"
    rm -rf "$UTF8_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PASS=0
FAIL=0

write_ring() {
    name="$1"
    payload_path="$2"
    cap="$3"
    out="$RING_DIR/$name.ring"
    /usr/bin/python3 - "$payload_path" "$out" "$cap" <<'PY'
import struct, sys
payload_path, out_path, cap_s = sys.argv[1], sys.argv[2], sys.argv[3]
cap = int(cap_s)
with open(payload_path, 'rb') as f:
    payload = f.read()
assert len(payload) <= cap, "payload exceeds cap"
header = struct.pack('<IIQQQ', 0x52455650, 0, len(payload), 0, 0)
body = payload + (b'\x00' * (cap - len(payload)))
with open(out_path, 'wb') as f:
    f.write(header)
    f.write(body)
PY
}

write_empty_ring() {
    name="$1"
    cap="$2"
    out="$RING_DIR/$name.ring"
    /usr/bin/python3 - "$out" "$cap" <<'PY'
import struct, sys
out_path, cap_s = sys.argv[1], sys.argv[2]
cap = int(cap_s)
header = struct.pack('<IIQQQ', 0x52455650, 0, 0, 0, 0)
with open(out_path, 'wb') as f:
    f.write(header)
    f.write(b'\x00' * cap)
PY
}

run_recover_and_get_hint() {
    uuid="$1"
    "$RECOVER" "$RING_DIR" 2>/dev/null \
        | awk -F '\t' -v u="$uuid" '$1 == u { print $4 }'
}

assert_eq() {
    label="$1"
    expected="$2"
    actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  PASS  %s\n' "$label"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n         expected: %s\n         actual:   %s\n' \
            "$label" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

CAP=4096

echo "== void-session-recover edge-case harness =="
echo "   workdir: $WORKDIR"
echo

# Case A: empty ring (write_offset=0) → 'empty'
echo "[case A] empty ring (write_offset=0)"
write_empty_ring "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" "$CAP"
hint=$(run_recover_and_get_hint "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
assert_eq "empty ring -> 'empty'" "empty" "$hint"
echo

# Case B: ANSI-only payload → '?'
echo "[case B] ANSI-only ring (no plain text paths)"
ansi_payload="$WORKDIR/ansi.bin"
/usr/bin/printf '\033[2J\033[H\033[31mred\033[0m\033[1;1H\033[?25l\033[?25h' \
    > "$ansi_payload"
write_ring "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" "$ansi_payload" "$CAP"
hint=$(run_recover_and_get_hint "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
assert_eq "ansi-only ring -> '?'" "?" "$hint"
echo

# Case C: multiple cd, last target ghost, earlier /private/tmp exists.
# Expectation: recover.sh walks back and picks the last EXISTING match.
echo "[case C] mixed cd history — pick last existing, not literal last"
mixed_payload="$WORKDIR/mixed.bin"
EXIST_C="/private/tmp"
GHOST_C="/tmp/this-path-does-not-exist-void-recover-test-9f8e7d6c"
/usr/bin/printf '$ cd %s\n%s $ ls\n$ cd %s\nbash: cd: %s: No such file or directory\n' \
    "$EXIST_C" "$EXIST_C" "$GHOST_C" "$GHOST_C" > "$mixed_payload"
write_ring "cccccccc-cccc-cccc-cccc-cccccccccccc" "$mixed_payload" "$CAP"
hint=$(run_recover_and_get_hint "cccccccc-cccc-cccc-cccc-cccccccccccc")
assert_eq "mixed history -> '/private/tmp' (last existing)" \
    "/private/tmp" "$hint"
echo

# Case D: UTF-8 path. recover.sh charset truncates at first non-ASCII byte;
# the ASCII prefix /tmp/void-recover-utf8- is not itself a dir, so the
# script falls through to "last raw match" — that prefix. Locks in:
# no crash, deterministic output, no garbled bytes downstream.
echo "[case D] UTF-8 path — deterministic ASCII prefix, no crash"
mkdir -p "$UTF8_DIR"
utf8_payload="$WORKDIR/utf8.bin"
/usr/bin/printf '$ cd %s\n%s $ pwd\n%s\n' "$UTF8_DIR" "$UTF8_DIR" "$UTF8_DIR" \
    > "$utf8_payload"
write_ring "dddddddd-dddd-dddd-dddd-dddddddddddd" "$utf8_payload" "$CAP"
hint=$(run_recover_and_get_hint "dddddddd-dddd-dddd-dddd-dddddddddddd")
assert_eq "utf-8 path -> ASCII prefix '/tmp/void-recover-utf8-' (regex limit)" \
    "/tmp/void-recover-utf8-" "$hint"
echo

# Case E: ring references an existing path verbatim. Use /private/tmp
# because bare /tmp fails the regex (requires at least one path-char after
# the recognized prefix).
echo "[case E] existing path -> exact match"
exist_payload="$WORKDIR/exist.bin"
/usr/bin/printf '$ cd /private/tmp\n/private/tmp $ pwd\n/private/tmp\n' \
    > "$exist_payload"
write_ring "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee" "$exist_payload" "$CAP"
hint=$(run_recover_and_get_hint "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")
assert_eq "existing /private/tmp -> '/private/tmp'" "/private/tmp" "$hint"
echo

# Smoke: recover.sh exits 0 on the populated dir.
echo "[smoke] recover.sh exits 0 on the populated dir"
if "$RECOVER" "$RING_DIR" >/dev/null 2>&1; then
    printf '  PASS  recover.sh exit code 0\n'
    PASS=$((PASS + 1))
else
    rc=$?
    printf '  FAIL  recover.sh exit code %s (expected 0)\n' "$rc"
    FAIL=$((FAIL + 1))
fi
echo

echo "== summary: $PASS passed, $FAIL failed =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
