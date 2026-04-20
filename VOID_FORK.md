# void — ghostty fork

**upstream:** [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)
**fork date:** 2026-04-21 (from upstream commit `c3c8572f7`)

## Why

void is a **ghostty-based AI-native terminal**. three non-negotiable directions:

1. **grid mode (first-class)** — N×M pane grid as a core surface concept, not a plugin / window-manager bolt-on. shared input routing, per-cell cwd, keyboard-grammar for grid navigation.
2. **AI-native I/O** — agent I/O protocol baked into the terminal layer alongside PTY. structured tool-call / token-stream aware channels, so running an agent does not require a wrapper process.
3. **perf-first** — speed, memory, GPU time, and syscall budgets are a tracked first-class concern. every PR reports delta against the ghostty baseline.

## non-goals

- being a drop-in ghostty replacement (void will diverge in UX)
- being a shell (void drives shells; does not replace them)

## Upstream relationship

the `upstream` git remote tracks ghostty. void will periodically rebase / merge upstream fixes that don't conflict with the three directions above. divergent changes (grid, AI I/O, perf rewrites) stay void-only unless ghostty upstream wants them.

## See also

- `.roadmap` — current phases
- `.own` — project rules (inherits hexa-lang .raw)
