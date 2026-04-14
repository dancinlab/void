#!/usr/bin/env bash
# install_void.sh — install /tmp/void_term into /Applications/VOID.app
# with **stable** ad-hoc code signature so TCC (Privacy & Security)
# remembers the user's Allow decisions across rebuilds + updates.
#
# Why this script exists:
#   macOS TCC keys file-access / automation prompts by the app's
#   Designated Requirement (DR). A plain ad-hoc `codesign -s -` embeds
#   the binary's cdhash into the DR, so rebuilding changes the DR and
#   the user sees "VOID would like to access …" again. We want: prompt
#   once at first install, never again on rebuild.
#
# Strategy:
#   1. Always pass  --identifier com.need-singularity.void — anchors
#      TCC records on a stable string instead of the volatile cdhash.
#   2. Sign **the whole bundle** (not just the Mach-O) with --deep so
#      the bundle's embedded _CodeSignature/CodeResources is rebuilt
#      cleanly — avoids the "resource envelope is obsolete" refusal
#      that would otherwise re-prompt on first launch.
#   3. Attach the same entitlements.plist every time so capability
#      grants (sandbox-off, library-validation-off, apple-events,
#      file-folder access rationale) are identical across versions.
#   4. Strip com.apple.quarantine AND com.apple.provenance — their
#      presence makes Gatekeeper treat the app as "just downloaded"
#      and forces a re-validation prompt.
#   5. Keep Info.plist from our repo template so NS*UsageDescription
#      keys are always present (TCC needs these to even offer an
#      "Always Allow" button).
#
# Run this after every build. The build_void.sh harness will be wired
# to invoke it on successful promotion.

set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
APP="${APP:-/Applications/VOID.app}"
BIN_SRC="${BIN_SRC:-/tmp/void_term}"
BIN_DST="$APP/Contents/MacOS/void_term"
INFO_SRC="$ROOT/pkg/Info.plist"
INFO_DST="$APP/Contents/Info.plist"
ENT="$ROOT/pkg/entitlements.plist"
BUNDLE_ID="com.need-singularity.void"

log() { printf '[install] %s\n' "$*"; }
die() { printf '[install] FATAL: %s\n' "$*" >&2; exit 1; }

# Pick the best available code-signing identity.
#   1. $CODESIGN_IDENTITY env var (explicit override).
#   2. Apple Development / Apple Distribution cert (stable DR, TCC
#      remembers across rebuilds — the whole point of this script).
#   3. Any Developer ID Application cert (production, also stable DR).
#   4. Fallback: ad-hoc `-` (TCC will re-prompt on every rebuild — the
#      script warns loudly so the user knows why prompts keep coming
#      back).
pick_identity() {
    if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
        printf '%s' "$CODESIGN_IDENTITY"; return
    fi
    local id
    # Prefer Apple Development (personal dev cert).
    id=$(security find-identity -v -p codesigning 2>/dev/null \
         | awk -F'"' '/Apple Development:/{print $2; exit}')
    if [[ -n "$id" ]]; then printf '%s' "$id"; return; fi
    # Then Developer ID Application (distribution).
    id=$(security find-identity -v -p codesigning 2>/dev/null \
         | awk -F'"' '/Developer ID Application:/{print $2; exit}')
    if [[ -n "$id" ]]; then printf '%s' "$id"; return; fi
    # Fallback: ad-hoc.
    printf -- '-'
}

[[ -f "$INFO_SRC" ]]  || die "missing Info.plist template: $INFO_SRC"
[[ -f "$ENT" ]]       || die "missing entitlements: $ENT"

# Auto-build if staged binary missing or sources newer. Skip with
# SKIP_BUILD=1 (e.g. when binary was just built externally).
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    log "ensuring fresh harness-approved binary via build_void.sh …"
    "$ROOT/scripts/build_void.sh" || die "build failed — no binary to install"
fi
[[ -x "$BIN_SRC" ]]   || die "missing staged binary: $BIN_SRC"

# 1. Ensure the .app skeleton exists. On first install, create it;
#    on update, keep whatever Resources (AppIcon etc.) already live there.
if [[ ! -d "$APP" ]]; then
  log "first install → creating bundle skeleton at $APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
fi

# 2. Replace Mach-O + Info.plist. Resources (icon, etc.) stay.
log "copy binary  $BIN_SRC → $BIN_DST"
cp "$BIN_SRC" "$BIN_DST"
chmod +x "$BIN_DST"

log "copy Info.plist $INFO_SRC → $INFO_DST"
cp "$INFO_SRC" "$INFO_DST"

# 3. Strip quarantine / provenance BEFORE signing. Attributes invalidate
#    the signature if present afterward.
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP" 2>/dev/null || true
  log "cleared xattrs (quarantine + provenance)"
fi

# 4. Re-sign the whole bundle with stable identifier + entitlements.
#    --force: replace any existing signature.
#    --deep:  walk into nested bundles / frameworks (none here, but
#             makes the signature envelope canonical).
#    --identifier: anchor the designated requirement on a stable string.
#    --options runtime: hardened runtime on; paired with entitlements
#                       that re-enable what we need (JIT, library
#                       validation off).
IDENTITY="$(pick_identity)"
if [[ "$IDENTITY" == "-" ]]; then
    log "⚠  no Apple Development / Developer ID cert found — using ad-hoc"
    log "⚠  TCC permissions WILL re-prompt on every rebuild."
    log "⚠  For one-time-approval, install a cert via Xcode → Settings → Accounts."
else
    log "signing identity: $IDENTITY"
fi
log "codesign --sign \"$IDENTITY\" --identifier $BUNDLE_ID"
codesign --force --deep --sign "$IDENTITY" \
  --identifier "$BUNDLE_ID" \
  --options runtime \
  --entitlements "$ENT" \
  "$APP" 2>&1 | sed 's/^/[install]   /'

# 5. Verify. If the signature isn't valid, TCC will reject it silently
#    and we'd be back to per-launch prompts.
log "verify signature …"
if ! codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/[install]   /'; then
  die "codesign verify failed"
fi
log "verify identifier matches …"
got_id=$(codesign -dv "$APP" 2>&1 | awk -F= '/^Identifier=/{print $2}')
[[ "$got_id" == "$BUNDLE_ID" ]] || die "identifier drift: got '$got_id' expected '$BUNDLE_ID'"

# 6. spctl assess is optional — ad-hoc sigs won't pass Gatekeeper's
#    notarization check but first-launch via Finder "Open anyway" is
#    enough. Log the status for visibility.
log "spctl assess (info only):"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/[install]   /' || true

if [[ "$IDENTITY" == "-" ]]; then
    sig_desc="ad-hoc (DR uses cdhash — TCC will re-prompt on rebuild)"
else
    sig_desc="$IDENTITY (DR cert-anchored — TCC persists across rebuilds)"
fi

cat <<EOF
[install] ✓ installed: $APP
[install]   bundle id: $BUNDLE_ID
[install]   signature: $sig_desc
[install]
[install] On first launch macOS prompts once per permission (Desktop,
[install] Documents, Downloads, etc.). Choose "Allow" — the Designated
[install] Requirement is stable across rebuilds + reinstalls, so macOS
[install] TCC will remember and NOT re-prompt on future builds.
EOF
