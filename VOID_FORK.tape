#!/usr/bin/env tape

@V := "tape" :: spec [active]
  version = "1.2"

@I id001 := "void_fork" :: identity-claim [d=2026-05-14 active]
  kind = "void — ghostty fork"
  brief = "**upstream:** [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty)"
  parent = "dancinlab/void"
  sibling-md = "VOID_FORK.md"

# ─── §Log (append @A / @D events here, chronological) ────────────────
# 
# Pre-existing log entries live in VOID_FORK.md.
# New per-domain history entries land here as typed events:
#
#   @A commit_<hash> :: <domain> [d=<YYYY-MM-DD> ok]
#     <- <prev-id>
#     => "<one-line description>"
#
#   @D <id> := "<decision-name>" :: <domain> [<grades>]
#     <- <evidence-id>
#     |> <verifier>
#
# See ~/core/tape/spec/tape.md for full grammar.
