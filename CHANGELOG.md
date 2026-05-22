# Changelog

## PLAN absorption + UPPERCASE — 2026-05-22

`PLAN.md` was a single-domain design doc (session-restore gap closure for P7
Phase B2) misnamed as a generic plan. Absorbed into a proper UPPERCASE domain
pair:

- `PLAN.md` → `SESSION-RESTORE.md` (live spec — gap analysis, patch v1 design,
  what's left, open questions).
- `PLAN.log.md` → `SESSION-RESTORE.log.md` (history — verification snapshot,
  cross-host build env, decision log).

Internal cross-references updated. No standalone `PLAN.md` remains.

## docs split — 2026-05-22

Per-domain spec/history file split applied to root-level `*.md` files (sidecar
commons @D g29):

- `PLAN.md` (mixed) — kept current spec (gap analysis, patch v1 design, what's
  left, open questions, related work). Extracted history-flavored sections to
  new `PLAN.log.md`: 2026-05-21 verification snapshot, cross-host build
  environment notes (mini), and the dated decision log.
- `LIMIT_BREAKTHROUGH.md` — pure current-state audit snapshot (§1 domain ID,
  §2 limits table, §3 per-limit assessment, §4 top opportunities, §6 refs).
  Left alone.
- `TAPE-AUDIT.md` — current snapshot (verdict block). Left alone.
- All other root `*.md` files (`AI_POLICY`, `CHANGELOG`, `CLAUDE`,
  `CONTRIBUTING`, `HACKING`, `LATTICE_POLICY`, `PACKAGING`, `README`,
  `VOID_FORK`) — left alone per the rule's keep-list.

## void hard-fork — 2026-04-25

void is a **hard-fork** of [Ghostty](https://github.com/ghostty-org/ghostty)
(Mitchell Hashimoto, MIT License). The `upstream` git remote has been removed;
subsequent changes are not eligible for upstream merge.

**Fork cutoff:** upstream commit `c3c8572f7` ("update zon2nix #12337"). At fork
time, `void/main` was 92 commits ahead of `upstream/main` and shared this
single merge base.

**Identity sweep applied 2026-04-25** (this commit):

- macOS bundle identifier namespace: `com.mitchellh.*` → `com.dancinlab.*`
  (Xcode `PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleIdentifier`,
  `src/build_config.zig` `bundle_id`, all Swift `Notification.Name` /
  `UserDefaults(suiteName:)` / `UTType` / `NSPasteboard` / menu identifiers)
- GTK D-Bus base application id: `com.mitchellh.void` → `com.dancinlab.void`
  (`src/apprt/gtk/build/info.zig`, all GTK class application/window/surface
  refs, `inspector-window.blp` icon, `ipc/new_window.zig` doc examples)
- Linux distribution paths: flatpak/snap/desktop/metainfo/icon install paths
  rebased to `com.dancinlab.void`
- gettext domain: `com.mitchellh.void` → `com.dancinlab.void`
  (`src/build/VoidI18n.zig`, all 53 locale `.po` headers, `.pot` rename)
- Renamed files to match new namespace:
  - `flatpak/com.mitchellh.void.yml` → `flatpak/com.dancinlab.void.yml`
  - `flatpak/com.mitchellh.void-debug.yml` → `flatpak/com.dancinlab.void-debug.yml`
  - `dist/linux/com.mitchellh.void.metainfo.xml.in` → `dist/linux/com.dancinlab.void.metainfo.xml.in`
  - `po/com.mitchellh.void.pot` → `po/com.dancinlab.void.pot`

**Not touched** (out of scope, separate cleanup):

- `com.mitchellh.ghostty` residue in `dist/linux/ghostty_nautilus.py`,
  `.github/workflows/flatpak.yml`, `.github/scripts/check-translations.sh`
  — these are pre-existing stale references from the original `Ghostty → Void`
  L3 rename (commit `964c9e32e`, 2026-04-21) that point at filenames which no
  longer exist; they will be cleaned up in a follow-up identity-cleanup commit.
- `com.mitchellh.fullscreenDidEnter` / `…DidExit` Notification names were also
  rebased in this sweep (internal namespace, no API contract).

**User-data migration on macOS:**

Existing TCC permissions (Full Disk Access, Accessibility, Automation) were
granted to `com.mitchellh.void` and do **not** transfer to
`com.dancinlab.void`. Re-grant is required after this fork. The bundled
`install.hexa` already runs `tccutil reset All` against the new bundle id;
the user must approve permission prompts on first launch of the rebuilt app.

User defaults stored under `com.mitchellh.void` (window state, custom icon,
preferences) will not be inherited by the new bundle id. This is intentional:
the new identity is a clean slate.

**Attribution preserved:**

- License: MIT (unchanged)
- Original copyright: Mitchell Hashimoto and the Ghostty contributors
- Source code ghostty references intentionally retained where they describe
  inherited behavior, vendored dependency hashes (`deps.files.ghostty.org`),
  C-ABI compatibility surface (`libghostty` → `libvoid` rename complete; old
  symbol names preserved where required for ABI stability), and benchmark
  comparison context (Δ vs ghostty perf budget per `README.md`).
- The original Ghostty git history is preserved on the `origin` remote
  (`dancinlab/void`); see `git log` for the unbroken chain back to the
  initial Ghostty commit.

## upstream Ghostty history — preserved below for attribution

Pre-fork commits inherit Ghostty's release notes; refer to
[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) tags up to
`c3c8572f7` for the canonical pre-fork changelog. void-specific divergence
prior to this hard-fork declaration lives in `git log upstream/main..HEAD`
(92 commits, 2026-04-21 → 2026-04-25), starting from the L3 rename commit
`964c9e32e` ("Ghostty → Void rebrand").
