# void Constitution

## Core Principles

### I. Grid as a First-Class Surface (NON-NEGOTIABLE)
N×M pane grid is a primary rendering surface — not a window-manager bolt-on, not a tmux-style multiplexer, not a tab-bar afterthought. When cell count `N` changes, the layout auto-rebalances by the rule `cols = ⌈√N⌉, rows = ⌈N/cols⌉, cols ≥ rows`. Every cell carries its own cwd/env; input can broadcast to all cells. The grid surface is a direct extension of Ghostty's renderer, not a layer above it.

### II. Ghostty Engine Inherited — Selective Cherry-Pick Upstream Sync
void is a hard fork of `ghostty-org/ghostty`. The engine — SIMD parser, Metal/OpenGL renderer, per-terminal threads — is carried unchanged. UX is the divergence layer; engine internals are not rewritten without explicit justification. Upstream sync uses selective cherry-picks; full Ghostty history and attribution are preserved. void is a UX divergence, not a drop-in replacement.

### III. Beta Honesty — Roadmap ≠ Feature (NON-NEGOTIABLE)
Only grid mode is implemented. The structured agent I/O channel (P3) and per-PR perf budget vs Ghostty baseline (P4) are roadmap items, NOT shipped features. Every public surface (README, docs, badges, demo videos) MUST distinguish shipped from planned. Bundling roadmap into shipped is an over-claim and is rejected at review.

### IV. AI Usage Policy (NON-NEGOTIABLE)
Outside contributions follow `AI_POLICY.md` without exception:
- All AI usage MUST be disclosed (tool name + extent of assistance).
- Human-in-the-loop MUST fully understand all submitted code — if the contributor cannot explain the change without AI assistance, the contribution is rejected.
- Issues and discussions may use AI assistance but require a human in the loop for review and editing.
- No AI-generated media (art / images / video / audio). Text and code only.

Maintainers are exempt at their discretion. Repeated bad-AI-driver contributions are blocked permanently (public denouncement list).

### V. Cross-Platform Parity at the Grid Layer
Shared zig core; native UI per platform — Swift on macOS, GTK on Linux. The grid surface contract (auto-rebalance, per-cell cwd/env, broadcast input) MUST be byte-for-byte equivalent across platforms; platform-native rendering (Metal vs OpenGL) lives below the contract. A grid-layer divergence is a regression.

## Repository Layout

```
void/
├── src/                  # zig shared core (engine + grid surface)
├── macos/                # Swift UI (Metal renderer)
├── linux/                # GTK UI (OpenGL renderer)
├── build.zig             # zig build entry
├── config.void           # default user config sample
├── AI_POLICY.md          # AI usage policy (binding for outside contributions)
├── CONTRIBUTING.md       # contributor guide (includes AI policy pointer)
├── CHANGELOG.md          # chronological log
├── docs/                 # design + user docs
└── .specify/             # Spec Kit pipeline artifacts (this constitution lives here)
```

(zig/swift/gtk source trees are conventional Ghostty-style; this layout names the void-specific surfaces only.)

## Development Workflow

1. **Surface change.** A grid surface change (rebalance rule, per-cell semantics, broadcast input behavior) requires a design note in `docs/design/` plus byte-equivalent behavior on both platforms before merge.
2. **Upstream sync.** New Ghostty commits land via cherry-pick with the original `Author:` preserved and a one-line note in `CHANGELOG.md` linking the upstream SHA. No `git merge` of the Ghostty branch — selective cherry-pick only.
3. **Roadmap surface.** P3 (structured agent I/O) and P4 (perf budget) live in `docs/design/roadmap.md`. Promotion from roadmap to shipped requires (a) implementation, (b) cross-platform parity test, (c) doc surface flip — all in the same PR.
4. **AI-assisted contribution.** Per `AI_POLICY.md`: disclose tool + extent in the PR description, demonstrate understanding in PR comments / review responses.

## Governance

- This constitution governs void repo-local concerns (grid surface, upstream sync discipline, beta honesty, AI policy enforcement, cross-platform parity).
- On AI usage by outside contributors, `AI_POLICY.md` is the authoritative document — this constitution mirrors and depends on it; the policy itself is the surface for contributors.
- Amendments land via PR that updates this file and bumps semver (MAJOR = principle removal/redefinition · MINOR = new principle / section · PATCH = wording).
- Complexity must be justified. Default = simpler.

**Version**: 1.0.0 | **Ratified**: 2026-05-21 | **Last Amended**: 2026-05-21
