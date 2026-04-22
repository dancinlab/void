#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <void/vt.h>

//! [grid-ref-traverse]
int main() {
  // Create a small terminal
  VoidTerminal terminal;
  VoidTerminalOptions opts = {
    .cols = 10,
    .rows = 3,
    .max_scrollback = 0,
  };
  VoidResult result = void_terminal_new(NULL, &terminal, opts);
  assert(result == VOID_SUCCESS);

  // Write some content so the grid has interesting data
  const char *text = "Hello!\r\n"    // Row 0: H e l l o !
                     "World\r\n"     // Row 1: W o r l d
                     "\033[1mBold";   // Row 2: B o l d (bold style)
  void_terminal_vt_write(
      terminal, (const uint8_t *)text, strlen(text));

  // Get terminal dimensions
  uint16_t cols, rows;
  void_terminal_get(terminal, VOID_TERMINAL_DATA_COLS, &cols);
  void_terminal_get(terminal, VOID_TERMINAL_DATA_ROWS, &rows);

  // Traverse the entire grid using grid refs
  for (uint16_t row = 0; row < rows; row++) {
    printf("Row %u: ", row);
    for (uint16_t col = 0; col < cols; col++) {
      // Resolve the point to a grid reference
      VoidGridRef ref = VOID_INIT_SIZED(VoidGridRef);
      VoidPoint pt = {
        .tag = VOID_POINT_TAG_ACTIVE,
        .value = { .coordinate = { .x = col, .y = row } },
      };
      result = void_terminal_grid_ref(terminal, pt, &ref);
      assert(result == VOID_SUCCESS);

      // Read the cell from the grid ref
      VoidCell cell;
      result = void_grid_ref_cell(&ref, &cell);
      assert(result == VOID_SUCCESS);

      // Check if the cell has text
      bool has_text = false;
      void_cell_get(cell, VOID_CELL_DATA_HAS_TEXT, &has_text);

      if (has_text) {
        uint32_t codepoint = 0;
        void_cell_get(cell, VOID_CELL_DATA_CODEPOINT, &codepoint);
        printf("%c", (char)codepoint);
      } else {
        printf(".");
      }
    }

    // Also inspect the row for wrap state
    VoidGridRef ref = VOID_INIT_SIZED(VoidGridRef);
    VoidPoint pt = {
      .tag = VOID_POINT_TAG_ACTIVE,
      .value = { .coordinate = { .x = 0, .y = row } },
    };
    void_terminal_grid_ref(terminal, pt, &ref);

    VoidRow grid_row;
    void_grid_ref_row(&ref, &grid_row);

    bool wrap = false;
    void_row_get(grid_row, VOID_ROW_DATA_WRAP, &wrap);
    printf(" (wrap=%s", wrap ? "true" : "false");

    // Check the style of the first cell with text
    VoidStyle style = VOID_INIT_SIZED(VoidStyle);
    void_grid_ref_style(&ref, &style);
    printf(", bold=%s)\n", style.bold ? "true" : "false");
  }

  void_terminal_free(terminal);
  return 0;
}
//! [grid-ref-traverse]
