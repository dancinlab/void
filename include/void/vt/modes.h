/**
 * @file modes.h
 *
 * Terminal mode utilities - pack and unpack ANSI/DEC mode identifiers.
 */

#ifndef VOID_VT_MODES_H
#define VOID_VT_MODES_H

/** @defgroup modes Mode Utilities
 *
 * Utilities for working with terminal modes. A mode is a compact
 * 16-bit representation of a terminal mode identifier that encodes both
 * the numeric mode value (up to 15 bits) and whether the mode is an ANSI
 * mode or a DEC private mode (?-prefixed).
 *
 * The packed layout (least-significant bit first) is:
 * - Bits 0–14: mode value (u15)
 * - Bit 15: ANSI flag (0 = DEC private mode, 1 = ANSI mode)
 *
 * ## Example
 *
 * @snippet c-vt-modes/src/main.c modes-pack-unpack
 *
 * ## DECRPM Report Encoding
 *
 * Use void_mode_report_encode() to encode a DECRPM response into a
 * caller-provided buffer:
 *
 * @snippet c-vt-modes/src/main.c modes-decrpm
 *
 * @{
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <void/vt/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @name ANSI Modes
 * Modes for standard ANSI modes.
 * @{
 */
#define VOID_MODE_KAM              (void_mode_new(2, true))    /**< Keyboard action (disable keyboard) */
#define VOID_MODE_INSERT           (void_mode_new(4, true))    /**< Insert mode */
#define VOID_MODE_SRM              (void_mode_new(12, true))   /**< Send/receive mode */
#define VOID_MODE_LINEFEED         (void_mode_new(20, true))   /**< Linefeed/new line mode */
/** @} */

/** @name DEC Private Modes
 * Modes for DEC private modes (?-prefixed).
 * @{
 */
#define VOID_MODE_DECCKM           (void_mode_new(1, false))   /**< Cursor keys */
#define VOID_MODE_132_COLUMN       (void_mode_new(3, false))   /**< 132/80 column mode */
#define VOID_MODE_SLOW_SCROLL      (void_mode_new(4, false))   /**< Slow scroll */
#define VOID_MODE_REVERSE_COLORS   (void_mode_new(5, false))   /**< Reverse video */
#define VOID_MODE_ORIGIN           (void_mode_new(6, false))   /**< Origin mode */
#define VOID_MODE_WRAPAROUND       (void_mode_new(7, false))   /**< Auto-wrap mode */
#define VOID_MODE_AUTOREPEAT       (void_mode_new(8, false))   /**< Auto-repeat keys */
#define VOID_MODE_X10_MOUSE        (void_mode_new(9, false))   /**< X10 mouse reporting */
#define VOID_MODE_CURSOR_BLINKING  (void_mode_new(12, false))  /**< Cursor blink */
#define VOID_MODE_CURSOR_VISIBLE   (void_mode_new(25, false))  /**< Cursor visible (DECTCEM) */
#define VOID_MODE_ENABLE_MODE_3    (void_mode_new(40, false))  /**< Allow 132 column mode */
#define VOID_MODE_REVERSE_WRAP     (void_mode_new(45, false))  /**< Reverse wrap */
#define VOID_MODE_ALT_SCREEN_LEGACY (void_mode_new(47, false)) /**< Alternate screen (legacy) */
#define VOID_MODE_KEYPAD_KEYS      (void_mode_new(66, false))  /**< Application keypad */
#define VOID_MODE_BACKARROW_KEY_MODE (void_mode_new(67, false))  /**< Backarrow key mode (DECBKM) */
#define VOID_MODE_LEFT_RIGHT_MARGIN (void_mode_new(69, false)) /**< Left/right margin mode */
#define VOID_MODE_NORMAL_MOUSE     (void_mode_new(1000, false)) /**< Normal mouse tracking */
#define VOID_MODE_BUTTON_MOUSE     (void_mode_new(1002, false)) /**< Button-event mouse tracking */
#define VOID_MODE_ANY_MOUSE        (void_mode_new(1003, false)) /**< Any-event mouse tracking */
#define VOID_MODE_FOCUS_EVENT      (void_mode_new(1004, false)) /**< Focus in/out events */
#define VOID_MODE_UTF8_MOUSE       (void_mode_new(1005, false)) /**< UTF-8 mouse format */
#define VOID_MODE_SGR_MOUSE        (void_mode_new(1006, false)) /**< SGR mouse format */
#define VOID_MODE_ALT_SCROLL       (void_mode_new(1007, false)) /**< Alternate scroll mode */
#define VOID_MODE_URXVT_MOUSE      (void_mode_new(1015, false)) /**< URxvt mouse format */
#define VOID_MODE_SGR_PIXELS_MOUSE (void_mode_new(1016, false)) /**< SGR-Pixels mouse format */
#define VOID_MODE_NUMLOCK_KEYPAD   (void_mode_new(1035, false)) /**< Ignore keypad with NumLock */
#define VOID_MODE_ALT_ESC_PREFIX   (void_mode_new(1036, false)) /**< Alt key sends ESC prefix */
#define VOID_MODE_ALT_SENDS_ESC    (void_mode_new(1039, false)) /**< Alt sends escape */
#define VOID_MODE_REVERSE_WRAP_EXT (void_mode_new(1045, false)) /**< Extended reverse wrap */
#define VOID_MODE_ALT_SCREEN       (void_mode_new(1047, false)) /**< Alternate screen */
#define VOID_MODE_SAVE_CURSOR      (void_mode_new(1048, false)) /**< Save cursor (DECSC) */
#define VOID_MODE_ALT_SCREEN_SAVE  (void_mode_new(1049, false)) /**< Alt screen + save cursor + clear */
#define VOID_MODE_BRACKETED_PASTE  (void_mode_new(2004, false)) /**< Bracketed paste mode */
#define VOID_MODE_SYNC_OUTPUT      (void_mode_new(2026, false)) /**< Synchronized output */
#define VOID_MODE_GRAPHEME_CLUSTER (void_mode_new(2027, false)) /**< Grapheme cluster mode */
#define VOID_MODE_COLOR_SCHEME_REPORT (void_mode_new(2031, false)) /**< Report color scheme */
#define VOID_MODE_IN_BAND_RESIZE   (void_mode_new(2048, false)) /**< In-band size reports */
/** @} */

/**
 * A packed 16-bit terminal mode.
 *
 * Encodes a mode value (bits 0–14) and an ANSI flag (bit 15) into a
 * single 16-bit integer. Use the inline helper functions to construct
 * and inspect modes rather than manipulating bits directly.
 */
typedef uint16_t VoidMode;

/**
 * Create a mode from a mode value and ANSI flag.
 *
 * @param value The numeric mode value (0–32767)
 * @param ansi true for an ANSI mode, false for a DEC private mode
 * @return The packed mode
 *
 * @ingroup modes
 */
static inline VoidMode void_mode_new(uint16_t value, bool ansi) {
    return (VoidMode)((value & 0x7FFF) | ((uint16_t)ansi << 15));
}

/**
 * Extract the numeric mode value from a mode.
 *
 * @param mode The mode
 * @return The mode value (0–32767)
 *
 * @ingroup modes
 */
static inline uint16_t void_mode_value(VoidMode mode) {
    return mode & 0x7FFF;
}

/**
 * Check whether a mode represents an ANSI mode.
 *
 * @param mode The mode
 * @return true if this is an ANSI mode, false if it is a DEC private mode
 *
 * @ingroup modes
 */
static inline bool void_mode_ansi(VoidMode mode) {
    return (mode >> 15) != 0;
}

/**
 * DECRPM report state values.
 *
 * These correspond to the Ps2 parameter in a DECRPM response
 * sequence (CSI ? Ps1 ; Ps2 $ y).
 */
typedef enum VOID_ENUM_TYPED {
    /** Mode is not recognized */
    VOID_MODE_REPORT_NOT_RECOGNIZED = 0,
    /** Mode is set (enabled) */
    VOID_MODE_REPORT_SET = 1,
    /** Mode is reset (disabled) */
    VOID_MODE_REPORT_RESET = 2,
    /** Mode is permanently set */
    VOID_MODE_REPORT_PERMANENTLY_SET = 3,
    /** Mode is permanently reset */
    VOID_MODE_REPORT_PERMANENTLY_RESET = 4,
    VOID_MODE_REPORT_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidModeReportState;

/**
 * Encode a DECRPM (DEC Private Mode Report) response sequence.
 *
 * Writes a mode report escape sequence into the provided buffer.
 * The generated sequence has the form:
 * - DEC private mode: CSI ? Ps1 ; Ps2 $ y
 * - ANSI mode:        CSI Ps1 ; Ps2 $ y
 *
 * If the buffer is too small, the function returns VOID_OUT_OF_SPACE
 * and writes the required buffer size to @p out_written. The caller can
 * then retry with a sufficiently sized buffer.
 *
 * @param mode The mode identifying the mode to report on
 * @param state The report state for this mode
 * @param buf Output buffer to write the encoded sequence into (may be NULL)
 * @param buf_len Size of the output buffer in bytes
 * @param[out] out_written On success, the number of bytes written. On
 *             VOID_OUT_OF_SPACE, the required buffer size.
 * @return VOID_SUCCESS on success, VOID_OUT_OF_SPACE if the buffer
 *         is too small
 */
VOID_API VoidResult void_mode_report_encode(
    VoidMode mode,
    VoidModeReportState state,
    char* buf,
    size_t buf_len,
    size_t* out_written);

#ifdef __cplusplus
}
#endif

/** @} */

#endif /* VOID_VT_MODES_H */
