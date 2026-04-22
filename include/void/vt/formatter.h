/**
 * @file formatter.h
 *
 * Format terminal content as plain text, VT sequences, or HTML.
 */

#ifndef VOID_VT_FORMATTER_H
#define VOID_VT_FORMATTER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <void/vt/allocator.h>
#include <void/vt/selection.h>
#include <void/vt/types.h>
#include <void/vt/terminal.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @defgroup formatter Formatter
 *
 * Format terminal content as plain text, VT sequences, or HTML.
 *
 * A formatter captures a reference to a terminal and formatting options.
 * It can be used repeatedly to produce output that reflects the current
 * terminal state at the time of each format call.
 *
 * The terminal must outlive the formatter.
 *
 * @{
 */

/**
 * Output format.
 *
 * @ingroup formatter
 */
typedef enum VOID_ENUM_TYPED {
  /** Plain text (no escape sequences). */
  VOID_FORMATTER_FORMAT_PLAIN,

  /** VT sequences preserving colors, styles, URLs, etc. */
  VOID_FORMATTER_FORMAT_VT,

  /** HTML with inline styles. */
  VOID_FORMATTER_FORMAT_HTML,
  VOID_FORMATTER_FORMAT_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidFormatterFormat;

/**
 * Extra screen state to include in styled output.
 *
 * @ingroup formatter
 */
typedef struct {
  /** Size of this struct in bytes. Must be set to sizeof(VoidFormatterScreenExtra). */
  size_t size;

  /** Emit cursor position using CUP (CSI H). */
  bool cursor;

  /** Emit current SGR style state based on the cursor's active style_id. */
  bool style;

  /** Emit current hyperlink state using OSC 8 sequences. */
  bool hyperlink;

  /** Emit character protection mode using DECSCA. */
  bool protection;

  /** Emit Kitty keyboard protocol state using CSI > u and CSI = sequences. */
  bool kitty_keyboard;

  /** Emit character set designations and invocations. */
  bool charsets;
} VoidFormatterScreenExtra;

/**
 * Extra terminal state to include in styled output.
 *
 * @ingroup formatter
 */
typedef struct {
  /** Size of this struct in bytes. Must be set to sizeof(VoidFormatterTerminalExtra). */
  size_t size;

  /** Emit the palette using OSC 4 sequences. */
  bool palette;

  /** Emit terminal modes that differ from their defaults using CSI h/l. */
  bool modes;

  /** Emit scrolling region state using DECSTBM and DECSLRM sequences. */
  bool scrolling_region;

  /** Emit tabstop positions by clearing all tabs and setting each one. */
  bool tabstops;

  /** Emit the present working directory using OSC 7. */
  bool pwd;

  /** Emit keyboard modes such as ModifyOtherKeys. */
  bool keyboard;

  /** Screen-level extras. */
  VoidFormatterScreenExtra screen;
} VoidFormatterTerminalExtra;

/**
 * Options for creating a terminal formatter.
 *
 * @ingroup formatter
 */
typedef struct {
  /** Size of this struct in bytes. Must be set to sizeof(VoidFormatterTerminalOptions). */
  size_t size;

  /** Output format to emit. */
  VoidFormatterFormat emit;

  /** Whether to unwrap soft-wrapped lines. */
  bool unwrap;

  /** Whether to trim trailing whitespace on non-blank lines. */
  bool trim;

  /** Extra terminal state to include in styled output. */
  VoidFormatterTerminalExtra extra;

  /** Optional selection to restrict output to a range.
   *  If NULL, the entire screen is formatted. */
  const VoidSelection *selection;
} VoidFormatterTerminalOptions;

/**
 * Create a formatter for a terminal's active screen.
 *
 * The terminal must outlive the formatter. The formatter stores a borrowed
 * reference to the terminal and reads its current state on each format call.
 *
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param formatter Pointer to store the created formatter handle
 * @param terminal The terminal to format (must not be NULL)
 * @param options Formatting options
 * @return VOID_SUCCESS on success, or an error code on failure
 *
 * @ingroup formatter
 */
VOID_API VoidResult void_formatter_terminal_new(
    const VoidAllocator* allocator,
    VoidFormatter* formatter,
    VoidTerminal terminal,
    VoidFormatterTerminalOptions options);

/**
 * Run the formatter and produce output into the caller-provided buffer.
 *
 * Each call formats the current terminal state. Pass NULL for buf to
 * query the required buffer size without writing any output; in that case
 * out_written receives the required size and the return value is
 * VOID_OUT_OF_SPACE.
 *
 * If the buffer is too small, returns VOID_OUT_OF_SPACE and sets
 * out_written to the required size. The caller can then retry with a
 * larger buffer.
 *
 * @param formatter The formatter handle (must not be NULL)
 * @param buf Pointer to the output buffer, or NULL to query size
 * @param buf_len Length of the output buffer in bytes
 * @param out_written Pointer to receive the number of bytes written,
 *                    or the required size on failure
 * @return VOID_SUCCESS on success, or an error code on failure
 *
 * @ingroup formatter
 */
VOID_API VoidResult void_formatter_format_buf(VoidFormatter formatter,
                                           uint8_t* buf,
                                           size_t buf_len,
                                           size_t* out_written);

/**
 * Run the formatter and return an allocated buffer with the output.
 *
 * Each call formats the current terminal state. The buffer is allocated
 * using the provided allocator (or the default allocator if NULL).
 * The caller is responsible for freeing the returned buffer with
 * void_free(), passing the same allocator (or NULL for the default)
 * that was used for the allocation.
 *
 * @param formatter The formatter handle (must not be NULL)
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param out_ptr Pointer to receive the allocated buffer
 * @param out_len Pointer to receive the length of the output in bytes
 * @return VOID_SUCCESS on success, VOID_OUT_OF_MEMORY on allocation
 *         failure
 *
 * @ingroup formatter
 */
VOID_API VoidResult void_formatter_format_alloc(VoidFormatter formatter,
                                             const VoidAllocator* allocator,
                                             uint8_t** out_ptr,
                                             size_t* out_len);

/**
 * Free a formatter instance.
 *
 * Releases all resources associated with the formatter. After this call,
 * the formatter handle becomes invalid.
 *
 * @param formatter The formatter handle to free (may be NULL)
 *
 * @ingroup formatter
 */
VOID_API void void_formatter_free(VoidFormatter formatter);

/** @} */

#ifdef __cplusplus
}
#endif

#endif /* VOID_VT_FORMATTER_H */
