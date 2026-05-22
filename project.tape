@V := "tape" :: spec [active]
  version = "1.2"

@I := "void" :: identity [active]
  kind   = "Grid-first terminal (Ghostty hard fork · N×M tiling as core rendering surface · 🕳️)"
  brief  = "Beta: grid mode only. P1 grid-mode, dancinlab hexagon icon."
  parent = "dancinlab"
  ssot   = "github.com/dancinlab/void (`hx install void`)"

@D grid_auto_layout := "N×M grid topology auto-rebalance" :: governance [required active]
  do   = "grid auto-layout preserves cols = ⌈√N⌉, rows = ⌈N/cols⌉, cols ≥ rows; per-cell cwd isolation"
  dont = "break grid topology on cell-count change · add manual resize handles / splits (auto-only)"
