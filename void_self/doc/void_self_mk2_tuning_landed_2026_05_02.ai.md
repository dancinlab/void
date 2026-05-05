---
schema: void/handoff/self_mk2_tuning/1
last_updated: 2026-05-02
ssot: void_self/doc/void_self_mk2_tuning_landed_2026_05_02.ai.md
related_raw: [270, 271, 272, 273]
related_doc:
  - .roadmap.grid
  - .roadmap.ai_native_io
  - .roadmap.session_persistence
  - .roadmap.perf_baseline
  - .roadmap.upstream_diverge
  - .roadmap.ai_native_structure
status: landed
session_type: bg-subagent
budget: $0 mac-local
destructive_ops: 0
---

# Void self mk2 tuning — 2026-05-02 land

## TL;DR

Void repo (97G — 92G in `.zig-cache` + 4G in `macos/` + 289M `.git`) audited at top-level. 6 domain `.roadmap.<domain>` files (mk2 JSONL format, header-on-line-2 convention) emitted additively without touching the existing root `.roadmap` (HEAD) or any other file. raw 270/271/272/273 (hive-origin core+module + README.ai.md + structural consistency + tier hierarchy) compliance evaluated separately as a meta SSOT — recommendation: **Option C defer** until hive 2026-06-01 promotion-day, since void = ghostty hard-fork (zig+swift) is structurally incompatible with the hexa-only core/<feature>/ + modules/<feature>/ prototype.

## §1 Phase 1 — top-level audit

### Disk usage (top consumers)

| Path | Size | Notes |
|---|---|---|
| `.zig-cache/` | 92G | zig build artifact cache (regenerable, gitignored) |
| `macos/` | 4G | Swift app bundle build artifacts (`macos/build/`) + xcframework + Sources |
| `.git/` | 289M | history preserved (back through Ghostty pre-fork chain to L3 rename `964c9e32e`) |
| `zig-out/` | 104M | zig build output (regenerable) |
| `src/` | 38M | shared zig core (parser, terminal, renderer, font, ipc, ...) |
| `test/` | 25M | test fixtures |
| `pkg/` | 17M | vendored packages |
| All others | < 6M each | config, docs, dist, state, vendor, ... |

### Key directory map (depth 1-2, source-relevant only)

```
void/
├── src/                        38M zig shared core
│   ├── benchmark/              perf-bench harness (inherited Ghostty)
│   ├── renderer/               metal/ + opengl/ + shaders/
│   ├── apprt/                  app runtime (gtk/ Linux)
│   ├── terminal/               parser + osc/ + tmux/ + kitty/ + search/
│   ├── termio/                 PersistRing.zig (P7 phase B1 land)
│   ├── input/                  binding (keybind) + key (linux/macos)
│   ├── font/                   opentype/ + face/ + shaper/ + sprite/
│   ├── simd/                   SIMD parser fast-path
│   ├── crash/                  crash reporter (.voidcrash envelope)
│   ├── cli/                    +show-config / +list-keybinds / +crash-report
│   ├── synthetic/              synthetic terminal generator
│   ├── lib/                    allocator/
│   ├── os/                     wasm/ + platform shims
│   ├── shell-integration/      bash/ + zsh/ + fish/ + nushell/ + elvish/
│   ├── build/                  build-system glue
│   ├── datastruct/             SplitTree (grid backbone)
│   ├── inspector/              widgets/
│   ├── stb/                    vendored stb_*
│   ├── terminfo/               terminfo database
│   ├── extra/                  misc
│   └── unicode/                tables
├── macos/                      4G swift app
│   ├── Sources/
│   │   ├── App/                AppDelegate, lifecycle
│   │   ├── Features/           Splits/ Terminal/ Settings/ Update/
│   │   │                       Custom App Icon/ Global Keybinds/
│   │   │                       AppleScript/ App Intents/ Services/
│   │   │                       Command Palette/ ClipboardConfirmation/
│   │   │                       QuickTerminal/ Secure Input/ About/
│   │   ├── Helpers/
│   │   └── Void/               app-shell wiring
│   ├── Tests/                  Update/ Terminal/ Splits/ Void/ Helpers/
│   ├── Void.xcodeproj/
│   ├── Assets.xcassets/        AppIcon.appiconset (hex squircle)
│   ├── VoidKit.xcframework/    macos-arm64_x86_64 + ios variants
│   └── build/                  Void.build (4G xcodebuild artifacts)
├── include/void/vt/            C-ABI surface for libvoid embedding
├── docs/design/                sighup-resistant-session.md (P7 canonical)
├── tool/                       build_iconset.hexa, install-to-applications.hexa,
│                               void-session-replay.sh
├── state/
│   ├── markers/                50 markers (49× install_*.marker + 1)
│   └── proposals/inventory.json (6-repo cross-repo bus)
├── .agents/                    commands/review-branch + skills/writing-commit-messages
├── .github/workflows/          11 workflows (build-fork.yml = canonical CI)
└── (root files: README.md, CHANGELOG.md, VOID_FORK.md, AI_POLICY.md,
   AGENTS.md, HACKING.md, CONTRIBUTING.md, PACKAGING.md, build.zig,
   CMakeLists.txt, project.hexa, install.hexa, .roadmap, .next-session)
```

### Recent commit context (last 100 commits scope)

- **P1 grid-mode toggle (cmd+G)** shipped 2026-04-22 (commits 326e5f159 → 56dc8bea6 → 15ad6e416) — flatten/explode + SplitTree.grid balanced reshape.
- **Hard-fork** declared 2026-04-25 (commit 0ce6453b0) — upstream remote removed, com.mitchellh.* → com.need-singularity.* sweep.
- **Pin-aware grid** + edge-snap (2026-04-30) — pinning mechanism with reflow on unpin (commits 0dbffbfc5, 5bca28af3, fd355894c, etc).
- **P7 session preservation** in flight (2026-04-28..29) — `src/termio/PersistRing.zig` + `tool/void-session-replay.sh` + 1s msync timer landed; phase B2 auto-replay pending.
- **UI polish** ongoing (2026-05-01..02) — green-dot completion indicator, dim-inactive overlay toggle, fullscreen opt-in via Window menu.

## §2 Phase 2 — domain `.roadmap.<domain>` emission

### 6 files emitted (additive only, no existing file modified)

| File | Kind | Status | Header summary |
|---|---|---|---|
| `.roadmap.grid` | domain | active | N×M grid mode (P1 done, P1.1 slot-spawn pending, P1.2 find-next rebind pending). 5 conditions, 2 blockers. |
| `.roadmap.ai_native_io` | domain | todo | Agent I/O channel alongside PTY (per VOID_FORK.md non-negotiable #2). 4 conditions, 2 blockers. Protocol spec freeze required first. |
| `.roadmap.session_persistence` | domain | wip | P7 abnormal-termination + scrollback. 3/5 conditions met (grid topology + PTY ring + manual recovery CLI), 2 pending (auto-replay phase B2 + graceful-save P2). 2 blockers. |
| `.roadmap.perf_baseline` | domain | todo | Perf-first budget tracking (Δ vs Ghostty). 1/4 conditions met (Build Fork CI). 2 blockers (namespace runners + variance methodology). |
| `.roadmap.upstream_diverge` | domain | active | Hard-fork policy. 4/5 conditions met (hard-fork + identity sweep + libvoid rename + attribution). 1 pending (cherry-pick decision matrix). 2 blockers. |
| `.roadmap.ai_native_structure` | meta | deferred | Cross-repo: hive raw 270/271/272/273 compliance evaluation. Recommendation Option C defer. 1/5 conditions met. 2 blockers. |

### Format conventions followed

- **mk2 JSONL** — header on line 2, one JSON entry per line afterward (mirrors `anima/.roadmap.iit4`, `anima/.roadmap.finalspark`, `anima/.roadmap.dual_pair_pilots`).
- **Header schema**: `{"type":"header","kind":"domain"|"meta","name":...,"mk":2,"goal":...,"required_conditions":[{id,desc,verifier,status,evidence,blocker_reason}],"blockers":[{id,desc,type,status,eta,resolution_path}],"status":...,"since":"2026-05-02","cross_links":[...]}`.
- **Meta variant** adds `perspective` (consumer/producer) + `origin_repo` + `provider_dependency` + optional `domains_spanned`.
- **Status enum**: `met` / `unmet` / `partial` for conditions; `open` / `blocked` / `mitigated` / `workaround` / `accepted` / `deferred` for blockers; `active` / `wip` / `todo` / `deferred` for top-level.

## §3 Phase 3 — raw 270/271/272/273 triplet plan

### Verbatim user-context interpretation

raw 270 + raw 271 + raw 272 + raw 273 = **hive-origin** core+module architecture quartet. void inherits as cross-repo consumer.

### Compatibility matrix

| Raw | Slug | hive scope | void applicability |
|---|---|---|---|
| 270 | core-module-architecture | `*/modules/<group>/*` dirs (hexa) | **STRUCTURAL MISMATCH** — void = zig src/<area>/ + swift Sources/Features/<area>/. No `core/<feature>/` + `modules/<feature>/` separation. |
| 271 | readme-ai-native | README.ai.md mandate per module group | **PARTIAL MISMATCH** — void has no module groups in hexa sense. `docs/design/*.md` could adopt frontmatter convention voluntarily. This handoff doc DOES use raw 271 frontmatter as a forward-compat gesture. |
| 272 | core-module-file-structure-consistency | folder/file naming snake_case + lint C1-C5 | **N/A** — void zig is camelCase + swift is PascalCase per language convention; raw 272 lint targets `.hexa` files only. |
| 273 | core-hierarchy-direction (T0/T1/T2) | hexa import direction matrix | **N/A** — zig has @import + build.zig module graph for dependency direction (its own enforcement). swift uses xcodeproj target deps. |

### 3-option decision tree

- **Option A — full opt-out**: write `.ai-native-readme-baseline` with single line `void: structural-incompatible (zig+swift hard-fork, raw 270/271/272/273 = hexa-only)`. Establishes precedent for non-hexa repos. Cost: 5 minutes. Risk: precedent might be misused.
- **Option B — per-language adaptation**: define "zig src/<area>/README.ai.md mandate" as a void-specific analog with raw 271-style frontmatter. Phase 1: pilot on 3 src/ areas (terminal, renderer, termio). Cost: ~3-5 hours per area + lint adaptation. Risk: divergence from hive prototype creates dual-maintenance burden.
- **Option C — defer (RECOMMENDED)**: monitor hive raw 270/271 warn→block promotion-day (2026-06-01). Pre-promotion: zero action. Post-promotion: re-evaluate based on whether hive enforcement applies to non-hexa repos at all (current hive scope: hexa core/modules only — void may be out of scope by default). Cost: $0. Risk: minimal — hive already ramps over 30d and targets hexa scope.

### Recommendation

**Option C** captured in `.roadmap.ai_native_structure`. Re-evaluation date: **2026-06-01**. If hive enforcement scope expands to non-hexa repos at promotion-day, decide A vs B at that point.

### Pre-emptive actions (zero-cost, applied this session)

- This handoff doc itself uses raw 271 YAML frontmatter (schema/last_updated/ssot/related_raw/related_doc/status) — forward-compat gesture, no enforcement consequence.

## §4 Caveats (raw 10 honest)

1. **97G size warning honored** — no `cp -R`/`mv`/destructive ops attempted. `.git/` (289M) not enumerated for history; only depth-1/2 directory listing + selective file reads.
2. **Domain selection is judgment-based** — 6 domains chosen from observed code areas + active phases (P1..P7). Alternative slicing (e.g. separate `.roadmap.font` for CJK fallback work, separate `.roadmap.icon` for hex squircle work) was rejected as too fine-grained for current state. CJK + icon are tracked as completed checkpoints in root `.roadmap` (HEAD).
3. **Existing root `.roadmap` (HEAD) NOT modified** — coexists with new `.roadmap.<domain>` files. Format precedent (anima): root `.roadmap` is human-prose phase tracker; `.roadmap.<domain>` is mk2 JSONL machine-parseable SSOT. Both layers serve different consumers.
4. **Verifiers are mostly static path checks** — not all verifiers are executable scripts. Status fields reflect best-effort assessment from commit history + file existence + grep counts; some `partial`/`unmet` may need manual confirmation.
5. **raw 270/271/272/273 compatibility analysis is preliminary** — no consultation with hive maintainers about whether non-hexa repos are in scope. Option C defer chosen specifically to surface this question via hive promotion-day decision rather than pre-empting it.
6. **No write to `.roadmap` or any other existing file** — additive only per session policy. If user wants the domain files referenced from root `.roadmap`, that requires a separate edit cycle with explicit approval.
7. **Marker convention** — single marker file `state/markers/void_self_mk2_tuning_landed.marker` written per silent-land marker protocol (feedback_silent_land_marker_protocol.md). Existing 50 markers preserved.

## §5 File index

### Created this session (additive, 7 files)

| Path | Purpose |
|---|---|
| `/Users/ghost/core/void/.roadmap.grid` | Domain SSOT — N×M grid mode |
| `/Users/ghost/core/void/.roadmap.ai_native_io` | Domain SSOT — agent I/O channel |
| `/Users/ghost/core/void/.roadmap.session_persistence` | Domain SSOT — P7 abnormal-termination |
| `/Users/ghost/core/void/.roadmap.perf_baseline` | Domain SSOT — perf budget |
| `/Users/ghost/core/void/.roadmap.upstream_diverge` | Domain SSOT — hard-fork policy |
| `/Users/ghost/core/void/.roadmap.ai_native_structure` | Meta SSOT — raw 270/271/272/273 compliance evaluation |
| `/Users/ghost/core/void/void_self/doc/void_self_mk2_tuning_landed_2026_05_02.ai.md` | This handoff doc |
| `/Users/ghost/core/void/state/markers/void_self_mk2_tuning_landed.marker` | Land-completion marker |

### Referenced (read-only, not modified)

- `/Users/ghost/core/void/.roadmap` (root, HEAD) — human-prose phase tracker
- `/Users/ghost/core/void/.next-session` — 2026-04-22 handoff
- `/Users/ghost/core/void/README.md`, `VOID_FORK.md`, `CHANGELOG.md`, `AGENTS.md`, `AI_POLICY.md`
- `/Users/ghost/core/void/project.hexa` — ssot_attrs[ai_native] formal subscription
- `/Users/ghost/core/void/docs/design/sighup-resistant-session.md` — P7 canonical
- `/Users/ghost/core/anima/.roadmap.iit4`, `.roadmap.finalspark`, `.roadmap.dual_pair_pilots`, `.roadmap.omega_cycle` — mk2 JSONL format precedents
- `/Users/ghost/core/hive/state/markers/raw_27{0,1,2,3}_*_landed.marker` — raw quartet land evidence
- `/Users/ghost/core/hive/docs/raw_270_271_warn_to_block_promotion_design.md` — Stage 1/2/3 timeline
