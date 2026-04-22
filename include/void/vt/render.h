/**
 * @file render.h
 *
 * Render state for creating high performance renderers.
 */

#ifndef VOID_VT_RENDER_H
#define VOID_VT_RENDER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <void/vt/allocator.h>
#include <void/vt/color.h>
#include <void/vt/terminal.h>
#include <void/vt/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @defgroup render Render State
 *
 * Represents the state required to render a visible screen (a viewport)
 * of a terminal instance. This is stateful and optimized for repeated
 * updates from a single terminal instance and only updating dirty regions
 * of the screen.
 *
 * The key design principle of this API is that it only needs read/write
 * access to the terminal instance during the update call. This allows
 * the render state to minimally impact terminal IO performance and also
 * allows the renderer to be safely multi-threaded (as long as a lock is 
 * held during the update call to ensure exclusive access to the terminal 
 * instance).
 *
 * The basic usage of this API is:
 *
 *   1. Create an empty render state
 *   2. Update it from a terminal instance whenever you need.
 *   3. Read from the render state to get the data needed to draw your frame.
 *
 * ## Dirty Tracking
 *
 * Dirty tracking is a key feature of the render state that allows renderers
 * to efficiently determine what parts of the screen have changed and only 
 * redraw changed regions.
 *
 * The render state API keeps track of dirty state at two independent layers:
 * a global dirty state that indicates whether the entire frame is clean, 
 * partially dirty, or fully dirty, and a per-row dirty state that allows 
 * tracking which rows in a partially dirty frame have changed. 
 *
 * The user of the render state API is expected to unset both of these.
 * The `update` call does not unset dirty state, it only updates it.
 *
 * An extremely important detail: setting one dirty state doesn't unset
 * the other. For example, setting the global dirty state to false does not
 * reset the row-level dirty flags. So, the caller of the render state API must
 * be careful to manage both layers of dirty state correctly. 
 *
 * ## Examples
 *
 * ### Creating and updating render state
 * @snippet c-vt-render/src/main.c render-state-update
 *
 * ### Checking dirty state
 * @snippet c-vt-render/src/main.c render-dirty-check
 *
 * ### Reading colors
 * @snippet c-vt-render/src/main.c render-colors
 *
 * ### Reading cursor state
 * @snippet c-vt-render/src/main.c render-cursor
 *
 * ### Iterating rows and cells
 * @snippet c-vt-render/src/main.c render-row-iterate
 *
 * ### Resetting dirty state after rendering
 * @snippet c-vt-render/src/main.c render-dirty-reset
 *
 * @{
 */

/**
 * Dirty state of a render state after update.
 *
 * @ingroup render
 */
typedef enum VOID_ENUM_TYPED {
  /** Not dirty at all; rendering can be skipped. */
  VOID_RENDER_STATE_DIRTY_FALSE = 0,

  /** Some rows changed; renderer can redraw incrementally. */
  VOID_RENDER_STATE_DIRTY_PARTIAL = 1,

  /** Global state changed; renderer should redraw everything. */
  VOID_RENDER_STATE_DIRTY_FULL = 2,
  VOID_RENDER_STATE_DIRTY_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidRenderStateDirty;

/**
 * Visual style of the cursor.
 *
 * @ingroup render
 */
typedef enum VOID_ENUM_TYPED {
  /** Bar cursor (DECSCUSR 5, 6). */
  VOID_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR = 0,

  /** Block cursor (DECSCUSR 1, 2). */
  VOID_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK = 1,

  /** Underline cursor (DECSCUSR 3, 4). */
  VOID_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE = 2,

  /** Hollow block cursor. */
  VOID_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW = 3,
  VOID_RENDER_STATE_CURSOR_VISUAL_STYLE_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidRenderStateCursorVisualStyle;

/**
 * Queryable data kinds for void_render_state_get().
 *
 * @ingroup render
 */
typedef enum VOID_ENUM_TYPED {
  /** Invalid / sentinel value. */
  VOID_RENDER_STATE_DATA_INVALID = 0,

  /** Viewport width in cells (uint16_t). */
  VOID_RENDER_STATE_DATA_COLS = 1,

  /** Viewport height in cells (uint16_t). */
  VOID_RENDER_STATE_DATA_ROWS = 2,

  /** Current dirty state (VoidRenderStateDirty). */
  VOID_RENDER_STATE_DATA_DIRTY = 3,

  /** Populate a pre-allocated VoidRenderStateRowIterator with row data
   *  from the render state (VoidRenderStateRowIterator). Row data is
   *  only valid as long as the underlying render state is not updated.
   *  It is unsafe to use row data after updating the render state.
   *  */
  VOID_RENDER_STATE_DATA_ROW_ITERATOR = 4,

  /** Default/current background color (VoidColorRgb). */
  VOID_RENDER_STATE_DATA_COLOR_BACKGROUND = 5,

  /** Default/current foreground color (VoidColorRgb). */
  VOID_RENDER_STATE_DATA_COLOR_FOREGROUND = 6,

  /** Cursor color when explicitly set by terminal state (VoidColorRgb).
   *  Returns VOID_INVALID_VALUE if no explicit cursor color is set;
   *  use COLOR_CURSOR_HAS_VALUE to check first. */
  VOID_RENDER_STATE_DATA_COLOR_CURSOR = 7,

  /** Whether an explicit cursor color is set (bool). */
  VOID_RENDER_STATE_DATA_COLOR_CURSOR_HAS_VALUE = 8,

  /** The active 256-color palette (VoidColorRgb[256]). */
  VOID_RENDER_STATE_DATA_COLOR_PALETTE = 9,

  /** The visual style of the cursor (VoidRenderStateCursorVisualStyle). */
  VOID_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE = 10,

  /** Whether the cursor is visible based on terminal modes (bool). */
  VOID_RENDER_STATE_DATA_CURSOR_VISIBLE = 11,

  /** Whether the cursor should blink based on terminal modes (bool). */
  VOID_RENDER_STATE_DATA_CURSOR_BLINKING = 12,

  /** Whether the cursor is at a password input field (bool). */
  VOID_RENDER_STATE_DATA_CURSOR_PASSWORD_INPUT = 13,

  /** Whether the cursor is visible within the viewport (bool).
   *  If false, the cursor viewport position values are undefined. */
  VOID_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE = 14,

  /** Cursor viewport x position in cells (uint16_t).
   *  Only valid when CURSOR_VIEWPORT_HAS_VALUE is true. */
  VOID_RENDER_STATE_DATA_CURSOR_VIEWPORT_X = 15,

  /** Cursor viewport y position in cells (uint16_t).
   *  Only valid when CURSOR_VIEWPORT_HAS_VALUE is true. */
  VOID_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y = 16,

  /** Whether the cursor is on the tail of a wide character (bool).
   *  Only valid when CURSOR_VIEWPORT_HAS_VALUE is true. */
  VOID_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL = 17,
  VOID_RENDER_STATE_DATA_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidRenderStateData;

/**
 * Settable options for void_render_state_set().
 *
 * @ingroup render
 */
typedef enum VOID_ENUM_TYPED {
  /** Set dirty state (VoidRenderStateDirty). */
  VOID_RENDER_STATE_OPTION_DIRTY = 0,
  VOID_RENDER_STATE_OPTION_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidRenderStateOption;

/**
 * Queryable data kinds for void_render_state_row_get().
 *
 * @ingroup render
 */
typedef enum VOID_ENUM_TYPED {
  /** Invalid / sentinel value. */
  VOID_RENDER_STATE_ROW_DATA_INVALID = 0,

  /** Whether the current row is dirty (bool). */
  VOID_RENDER_STATE_ROW_DATA_DIRTY = 1,

  /** The raw row value (VoidRow). */
  VOID_RENDER_STATE_ROW_DATA_RAW = 2,

  /** Populate a pre-allocated VoidRenderStateRowCells with cell data for
   *  the current row (VoidRenderStateRowCells). Cell data is only 
   *  valid as long as the underlying render state is not updated. 
   *  It is unsafe to use cell data after updating the render state. */
  VOID_RENDER_STATE_ROW_DATA_CELLS = 3,
  VOID_RENDER_STATE_ROW_DATA_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidRenderStateRowData;

/**
 * Settable options for void_render_state_row_set().
 *
 * @ingroup render
 */
typedef enum VOID_ENUM_TYPED {
  /** Set dirty state for the current row (bool). */
  VOID_RENDER_STATE_ROW_OPTION_DIRTY = 0,
  VOID_RENDER_STATE_ROW_OPTION_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidRenderStateRowOption;

/**
 * Render-state color information.
 *
 * This struct uses the sized-struct ABI pattern. Initialize with
 * VOID_INIT_SIZED(VoidRenderStateColors) before calling
 * void_render_state_colors_get().
 *
 * Example:
 * @code
 * VoidRenderStateColors colors = VOID_INIT_SIZED(VoidRenderStateColors);
 * VoidResult result = void_render_state_colors_get(state, &colors);
 * @endcode
 *
 * @ingroup render
 */
typedef struct {
  /** Size of this struct in bytes. Must be set to sizeof(VoidRenderStateColors). */
  size_t size;

  /** The default/current background color for the render state. */
  VoidColorRgb background;

  /** The default/current foreground color for the render state. */
  VoidColorRgb foreground;

  /** The cursor color when explicitly set by terminal state. */
  VoidColorRgb cursor;

  /** 
   * True when cursor contains a valid explicit cursor color value. 
   * If this is false, the cursor color should be ignored; it will 
   * contain undefined data.
   * */
  bool cursor_has_value;

  /** The active 256-color palette for this render state. */
  VoidColorRgb palette[256];
} VoidRenderStateColors;

/**
 * Create a new render state instance.
 *
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param state Pointer to store the created render state handle
 * @return VOID_SUCCESS on success, VOID_OUT_OF_MEMORY on allocation
 * failure
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_new(const VoidAllocator* allocator,
                                       VoidRenderState* state);

/**
 * Free a render state instance.
 *
 * Releases all resources associated with the render state. After this call,
 * the render state handle becomes invalid.
 *
 * @param state The render state handle to free (may be NULL)
 *
 * @ingroup render
 */
VOID_API void void_render_state_free(VoidRenderState state);

/**
 * Update a render state instance from a terminal.
 *
 * This consumes terminal/screen dirty state in the same way as the internal
 * render state update path.
 *
 * @param state The render state handle (NULL returns VOID_INVALID_VALUE)
 * @param terminal The terminal handle to read from (NULL returns VOID_INVALID_VALUE)
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if `state` or
 * `terminal` is NULL, VOID_OUT_OF_MEMORY if updating the state requires
 * allocation and that allocation fails
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_update(VoidRenderState state,
                                          VoidTerminal terminal);

/**
 * Get a value from a render state.
 *
 * The `out` pointer must point to a value of the type corresponding to the
 * requested data kind (see VoidRenderStateData).
 *
 * @param state The render state handle (NULL returns VOID_INVALID_VALUE)
 * @param data The data kind to query
 * @param[out] out Pointer to receive the queried value
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if `state` is
 *         NULL or `data` is not a recognized enum value
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_get(VoidRenderState state,
                                        VoidRenderStateData data,
                                        void* out);

/**
 * Get multiple data fields from a render state in a single call.
 *
 * Each element in the keys array specifies a data kind, and the
 * corresponding element in the values array receives the result.
 *
 * Processing stops at the first error; on success out_written
 * is set to count, on error it is set to the index of the
 * failing key (i.e. the number of values successfully written).
 *
 * @param state The render state handle (NULL returns VOID_INVALID_VALUE)
 * @param count Number of key/value pairs
 * @param keys Array of data kinds to query
 * @param values Array of output pointers (types must match each key's
 *               documented output type)
 * @param[out] out_written On return, receives the number of values
 *             successfully written (may be NULL)
 * @return VOID_SUCCESS if all queries succeed
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_get_multi(
    VoidRenderState state,
    size_t count,
    const VoidRenderStateData* keys,
    void** values,
    size_t* out_written);

/**
 * Set an option on a render state.
 *
 * The `value` pointer must point to a value of the type corresponding to the
 * requested option kind (see VoidRenderStateOption).
 *
 * @param state The render state handle (NULL returns VOID_INVALID_VALUE)
 * @param option The option to set
 * @param[in] value Pointer to the value to set (NULL returns
 *            VOID_INVALID_VALUE)
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if `state` or
 *         `value` is NULL
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_set(VoidRenderState state,
                                       VoidRenderStateOption option,
                                       const void* value);

/**
 * Get the current color information from a render state.
 *
 * This writes as many fields as fit in the caller-provided sized struct.
 * `out_colors->size` must be set by the caller (typically via
 * VOID_INIT_SIZED(VoidRenderStateColors)).
 *
 * @param state The render state handle (NULL returns VOID_INVALID_VALUE)
 * @param[out] out_colors Sized output struct to receive render-state colors
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if `state` or
 *         `out_colors` is NULL, or if `out_colors->size` is smaller than
 *         `sizeof(size_t)`
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_colors_get(VoidRenderState state,
                                              VoidRenderStateColors* out_colors);

/**
 * Create a new row iterator instance.
 *
 * All fields except the allocator are left undefined until populated
 * via void_render_state_get() with
 * VOID_RENDER_STATE_DATA_ROW_ITERATOR.
 *
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param[out] out_iterator On success, receives the created iterator handle
 * @return VOID_SUCCESS on success, VOID_OUT_OF_MEMORY on allocation
 *         failure
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_row_iterator_new(
    const VoidAllocator* allocator,
    VoidRenderStateRowIterator* out_iterator);

/**
 * Free a render-state row iterator.
 *
 * @param iterator The iterator handle to free (may be NULL)
 *
 * @ingroup render
 */
VOID_API void void_render_state_row_iterator_free(VoidRenderStateRowIterator iterator);

/**
 * Move a render-state row iterator to the next row.
 *
 * Returns true if the iterator moved successfully and row data is
 * available to read at the new position.
 *
 * @param iterator The iterator handle to advance (may be NULL)
 * @return true if advanced to the next row, false if `iterator` is
 *         NULL or if the iterator has reached the end
 *
 * @ingroup render
 */
VOID_API bool void_render_state_row_iterator_next(VoidRenderStateRowIterator iterator);

/**
 * Get a value from the current row in a render-state row iterator.
 *
 * The `out` pointer must point to a value of the type corresponding to the
 * requested data kind (see VoidRenderStateRowData).
 * Call void_render_state_row_iterator_next() at least once before
 * calling this function.
 *
 * @param iterator The iterator handle to query (NULL returns VOID_INVALID_VALUE)
 * @param data The data kind to query
 * @param[out] out Pointer to receive the queried value
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if
 *         `iterator` is NULL or the iterator is not positioned on a row
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_row_get(
    VoidRenderStateRowIterator iterator,
    VoidRenderStateRowData data,
    void* out);

/**
 * Get multiple data fields from the current row in a single call.
 *
 * Each element in the keys array specifies a data kind, and the
 * corresponding element in the values array receives the result.
 *
 * Processing stops at the first error; on success out_written
 * is set to count, on error it is set to the index of the
 * failing key (i.e. the number of values successfully written).
 *
 * @param iterator The iterator handle (NULL returns VOID_INVALID_VALUE)
 * @param count Number of key/value pairs
 * @param keys Array of data kinds to query
 * @param values Array of output pointers (types must match each key's
 *               documented output type)
 * @param[out] out_written On return, receives the number of values
 *             successfully written (may be NULL)
 * @return VOID_SUCCESS if all queries succeed
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_row_get_multi(
    VoidRenderStateRowIterator iterator,
    size_t count,
    const VoidRenderStateRowData* keys,
    void** values,
    size_t* out_written);

/**
 * Set an option on the current row in a render-state row iterator.
 *
 * The `value` pointer must point to a value of the type corresponding to the
 * requested option kind (see VoidRenderStateRowOption).
 * Call void_render_state_row_iterator_next() at least once before
 * calling this function.
 *
 * @param iterator The iterator handle to update (NULL returns VOID_INVALID_VALUE)
 * @param option The option to set
 * @param[in] value Pointer to the value to set (NULL returns
 *            VOID_INVALID_VALUE)
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if
 *         `iterator` is NULL or the iterator is not positioned on a row
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_row_set(
    VoidRenderStateRowIterator iterator,
    VoidRenderStateRowOption option,
    const void* value);

/**
 * Create a new row cells instance.
 *
 * All fields except the allocator are left undefined until populated
 * via void_render_state_row_get() with
 * VOID_RENDER_STATE_ROW_DATA_CELLS.
 *
 * You can reuse this value repeatedly with void_render_state_row_get() to 
 * avoid allocating a new cells container for every row.
 *
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param[out] out_cells On success, receives the created row cells handle
 * @return VOID_SUCCESS on success, VOID_OUT_OF_MEMORY on allocation
 *         failure
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_row_cells_new(
    const VoidAllocator* allocator,
    VoidRenderStateRowCells* out_cells);

/**
 * Queryable data kinds for void_render_state_row_cells_get().
 *
 * @ingroup render
 */
typedef enum VOID_ENUM_TYPED {
  /** Invalid / sentinel value. */
  VOID_RENDER_STATE_ROW_CELLS_DATA_INVALID = 0,

  /** The raw cell value (VoidCell). */
  VOID_RENDER_STATE_ROW_CELLS_DATA_RAW = 1,

  /** The style for the current cell (VoidStyle). */
  VOID_RENDER_STATE_ROW_CELLS_DATA_STYLE = 2,

  /** The total number of grapheme codepoints including the base codepoint
   *  (uint32_t). Returns 0 if the cell has no text. */
  VOID_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN = 3,

  /** Write grapheme codepoints into a caller-provided buffer (uint32_t*).
   *  The buffer must be at least graphemes_len elements. The base codepoint
   *  is written first, followed by any extra codepoints. */
  VOID_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF = 4,

  /** The resolved background color of the cell (VoidColorRgb).
   *  Flattens the three possible sources: content-tag bg_color_rgb,
   *  content-tag bg_color_palette (looked up in the palette), or the
   *  style's bg_color. Returns VOID_INVALID_VALUE if the cell has
   *  no background color, in which case the caller should use whatever
   *  default background color it wants (e.g. the terminal background). */
  VOID_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR = 5,

  /** The resolved foreground color of the cell (VoidColorRgb).
   *  Resolves palette indices through the palette. Bold color handling
   *  is not applied; the caller should handle bold styling separately.
   *  Returns VOID_INVALID_VALUE if the cell has no explicit foreground
   *  color, in which case the caller should use whatever default foreground
   *  color it wants (e.g. the terminal foreground). */
  VOID_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR = 6,
  VOID_RENDER_STATE_ROW_CELLS_DATA_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidRenderStateRowCellsData;

/**
 * Move a render-state row cells iterator to the next cell.
 *
 * Returns true if the iterator moved successfully and cell data is
 * available to read at the new position.
 *
 * @param cells The row cells handle to advance (may be NULL)
 * @return true if advanced to the next cell, false if `cells` is
 *         NULL or if the iterator has reached the end
 *
 * @ingroup render
 */
VOID_API bool void_render_state_row_cells_next(VoidRenderStateRowCells cells);

/**
 * Move a render-state row cells iterator to a specific column.
 *
 * Positions the iterator at the given x (column) index so that
 * subsequent reads return data for that cell.
 *
 * @param cells The row cells handle to reposition (NULL returns
 *        VOID_INVALID_VALUE)
 * @param x The zero-based column index to select
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if `cells`
 *         is NULL or `x` is out of range
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_row_cells_select(
    VoidRenderStateRowCells cells, uint16_t x);

/**
 * Get a value from the current cell in a render-state row cells iterator.
 *
 * The `out` pointer must point to a value of the type corresponding to the
 * requested data kind (see VoidRenderStateRowCellsData).
 * Call void_render_state_row_cells_next() or
 * void_render_state_row_cells_select() at least once before
 * calling this function.
 *
 * @param cells The row cells handle to query (NULL returns VOID_INVALID_VALUE)
 * @param data The data kind to query
 * @param[out] out Pointer to receive the queried value
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if
 *         `cells` is NULL or the iterator is not positioned on a cell
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_row_cells_get(
    VoidRenderStateRowCells cells,
    VoidRenderStateRowCellsData data,
    void* out);

/**
 * Get multiple data fields from the current cell in a single call.
 *
 * Each element in the keys array specifies a data kind, and the
 * corresponding element in the values array receives the result.
 *
 * Processing stops at the first error; on success out_written
 * is set to count, on error it is set to the index of the
 * failing key (i.e. the number of values successfully written).
 *
 * @param cells The row cells handle (NULL returns VOID_INVALID_VALUE)
 * @param count Number of key/value pairs
 * @param keys Array of data kinds to query
 * @param values Array of output pointers (types must match each key's
 *               documented output type)
 * @param[out] out_written On return, receives the number of values
 *             successfully written (may be NULL)
 * @return VOID_SUCCESS if all queries succeed
 *
 * @ingroup render
 */
VOID_API VoidResult void_render_state_row_cells_get_multi(
    VoidRenderStateRowCells cells,
    size_t count,
    const VoidRenderStateRowCellsData* keys,
    void** values,
    size_t* out_written);

/**
 * Free a row cells instance.
 *
 * @param cells The row cells handle to free (may be NULL)
 *
 * @ingroup render
 */
VOID_API void void_render_state_row_cells_free(VoidRenderStateRowCells cells);

/** @} */

#ifdef __cplusplus
}
#endif

#endif /* VOID_VT_RENDER_H */
