/**
 * @file encoder.h
 *
 * Mouse event encoding to terminal escape sequences.
 */

#ifndef VOID_VT_MOUSE_ENCODER_H
#define VOID_VT_MOUSE_ENCODER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <void/vt/allocator.h>
#include <void/vt/mouse/event.h>
#include <void/vt/terminal.h>
#include <void/vt/types.h>

/**
 * Opaque handle to a mouse encoder instance.
 *
 * This handle represents a mouse encoder that converts normalized
 * mouse events into terminal escape sequences.
 *
 * @ingroup mouse
 */
typedef struct VoidMouseEncoderImpl *VoidMouseEncoder;

/**
 * Mouse tracking mode.
 *
 * @ingroup mouse
 */
typedef enum VOID_ENUM_TYPED {
  /** Mouse reporting disabled. */
  VOID_MOUSE_TRACKING_NONE = 0,

  /** X10 mouse mode. */
  VOID_MOUSE_TRACKING_X10 = 1,

  /** Normal mouse mode (button press/release only). */
  VOID_MOUSE_TRACKING_NORMAL = 2,

  /** Button-event tracking mode. */
  VOID_MOUSE_TRACKING_BUTTON = 3,

  /** Any-event tracking mode. */
  VOID_MOUSE_TRACKING_ANY = 4,
  VOID_MOUSE_TRACKING_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidMouseTrackingMode;

/**
 * Mouse output format.
 *
 * @ingroup mouse
 */
typedef enum VOID_ENUM_TYPED {
  VOID_MOUSE_FORMAT_X10 = 0,
  VOID_MOUSE_FORMAT_UTF8 = 1,
  VOID_MOUSE_FORMAT_SGR = 2,
  VOID_MOUSE_FORMAT_URXVT = 3,
  VOID_MOUSE_FORMAT_SGR_PIXELS = 4,
  VOID_MOUSE_FORMAT_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidMouseFormat;

/**
 * Mouse encoder size and geometry context.
 *
 * This describes the rendered terminal geometry used to convert
 * surface-space positions into encoded coordinates.
 *
 * @ingroup mouse
 */
typedef struct {
  /** Size of this struct in bytes. Must be set to sizeof(VoidMouseEncoderSize). */
  size_t size;

  /** Full screen width in pixels. */
  uint32_t screen_width;

  /** Full screen height in pixels. */
  uint32_t screen_height;

  /** Cell width in pixels. Must be non-zero. */
  uint32_t cell_width;

  /** Cell height in pixels. Must be non-zero. */
  uint32_t cell_height;

  /** Top padding in pixels. */
  uint32_t padding_top;

  /** Bottom padding in pixels. */
  uint32_t padding_bottom;

  /** Right padding in pixels. */
  uint32_t padding_right;

  /** Left padding in pixels. */
  uint32_t padding_left;
} VoidMouseEncoderSize;

/**
 * Mouse encoder option identifiers.
 *
 * These values are used with void_mouse_encoder_setopt() to configure
 * the behavior of the mouse encoder.
 *
 * @ingroup mouse
 */
typedef enum VOID_ENUM_TYPED {
  /** Mouse tracking mode (value: VoidMouseTrackingMode). */
  VOID_MOUSE_ENCODER_OPT_EVENT = 0,

  /** Mouse output format (value: VoidMouseFormat). */
  VOID_MOUSE_ENCODER_OPT_FORMAT = 1,

  /** Renderer size context (value: VoidMouseEncoderSize). */
  VOID_MOUSE_ENCODER_OPT_SIZE = 2,

  /** Whether any mouse button is currently pressed (value: bool). */
  VOID_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED = 3,

  /** Whether to enable motion deduplication by last cell (value: bool). */
  VOID_MOUSE_ENCODER_OPT_TRACK_LAST_CELL = 4,
  VOID_MOUSE_ENCODER_OPT_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidMouseEncoderOption;

/**
 * Create a new mouse encoder instance.
 *
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param encoder Pointer to store the created encoder handle
 * @return VOID_SUCCESS on success, or an error code on failure
 *
 * @ingroup mouse
 */
VOID_API VoidResult void_mouse_encoder_new(const VoidAllocator *allocator,
                                        VoidMouseEncoder *encoder);

/**
 * Free a mouse encoder instance.
 *
 * @param encoder The encoder handle to free (may be NULL)
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_encoder_free(VoidMouseEncoder encoder);

/**
 * Set an option on the mouse encoder.
 *
 * A null pointer value does nothing. It does not reset to defaults.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param option The option to set
 * @param value Pointer to option value (type depends on option)
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_encoder_setopt(VoidMouseEncoder encoder,
                                  VoidMouseEncoderOption option,
                                  const void *value);

/**
 * Set encoder options from a terminal's current state.
 *
 * This sets tracking mode and output format from terminal state.
 * It does not modify size or any-button state.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param terminal The terminal handle, must not be NULL
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_encoder_setopt_from_terminal(VoidMouseEncoder encoder,
                                                VoidTerminal terminal);

/**
 * Reset internal encoder state.
 *
 * This clears motion deduplication state (last tracked cell).
 *
 * @param encoder The encoder handle (may be NULL)
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_encoder_reset(VoidMouseEncoder encoder);

/**
 * Encode a mouse event into a terminal escape sequence.
 *
 * Not all mouse events produce output. In such cases this returns
 * VOID_SUCCESS with out_len set to 0.
 *
 * If the output buffer is too small, this returns VOID_OUT_OF_SPACE
 * and out_len contains the required size.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param event The mouse event to encode, must not be NULL
 * @param out_buf Buffer to write encoded bytes to, or NULL to query required size
 * @param out_buf_size Size of out_buf in bytes
 * @param out_len Pointer to store bytes written (or required bytes on failure)
 * @return VOID_SUCCESS on success, VOID_OUT_OF_SPACE if buffer is too small,
 *         or another error code
 *
 * @ingroup mouse
 */
VOID_API VoidResult void_mouse_encoder_encode(VoidMouseEncoder encoder,
                                           VoidMouseEvent event,
                                           char *out_buf,
                                           size_t out_buf_size,
                                           size_t *out_len);

#endif /* VOID_VT_MOUSE_ENCODER_H */
