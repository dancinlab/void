/**
 * @file encoder.h
 *
 * Key event encoding to terminal escape sequences.
 */

#ifndef VOID_VT_KEY_ENCODER_H
#define VOID_VT_KEY_ENCODER_H

#include <stddef.h>
#include <stdint.h>
#include <void/vt/types.h>
#include <void/vt/allocator.h>
#include <void/vt/terminal.h>
#include <void/vt/key/event.h>

/**
 * Opaque handle to a key encoder instance.
 *
 * This handle represents a key encoder that converts key events into terminal
 * escape sequences.
 *
 * @ingroup key
 */
typedef struct VoidKeyEncoderImpl *VoidKeyEncoder;

/**
 * Kitty keyboard protocol flags.
 *
 * Bitflags representing the various modes of the Kitty keyboard protocol.
 * These can be combined using bitwise OR operations. Valid values all
 * start with `VOID_KITTY_KEY_`.
 *
 * @ingroup key
 */
typedef uint8_t VoidKittyKeyFlags;

/** Kitty keyboard protocol disabled (all flags off) */
#define VOID_KITTY_KEY_DISABLED 0

/** Disambiguate escape codes */
#define VOID_KITTY_KEY_DISAMBIGUATE (1 << 0)

/** Report key press and release events */
#define VOID_KITTY_KEY_REPORT_EVENTS (1 << 1)

/** Report alternate key codes */
#define VOID_KITTY_KEY_REPORT_ALTERNATES (1 << 2)

/** Report all key events including those normally handled by the terminal */
#define VOID_KITTY_KEY_REPORT_ALL (1 << 3)

/** Report associated text with key events */
#define VOID_KITTY_KEY_REPORT_ASSOCIATED (1 << 4)

/** All Kitty keyboard protocol flags enabled */
#define VOID_KITTY_KEY_ALL (VOID_KITTY_KEY_DISAMBIGUATE | VOID_KITTY_KEY_REPORT_EVENTS | VOID_KITTY_KEY_REPORT_ALTERNATES | VOID_KITTY_KEY_REPORT_ALL | VOID_KITTY_KEY_REPORT_ASSOCIATED)

/**
 * macOS option key behavior.
 *
 * Determines whether the "option" key on macOS is treated as "alt" or not.
 * See the Void `macos-option-as-alt` configuration option for more details.
 *
 * @ingroup key
 */
typedef enum VOID_ENUM_TYPED {
    /** Option key is not treated as alt */
    VOID_OPTION_AS_ALT_FALSE = 0,
    /** Option key is treated as alt */
    VOID_OPTION_AS_ALT_TRUE = 1,
    /** Only left option key is treated as alt */
    VOID_OPTION_AS_ALT_LEFT = 2,
    /** Only right option key is treated as alt */
    VOID_OPTION_AS_ALT_RIGHT = 3,
    VOID_OPTION_AS_ALT_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidOptionAsAlt;

/**
 * Key encoder option identifiers.
 *
 * These values are used with void_key_encoder_setopt() to configure
 * the behavior of the key encoder.
 *
 * @ingroup key
 */
typedef enum VOID_ENUM_TYPED {
    /** Terminal DEC mode 1: cursor key application mode (value: bool) */
    VOID_KEY_ENCODER_OPT_CURSOR_KEY_APPLICATION = 0,

    /** Terminal DEC mode 66: keypad key application mode (value: bool) */
    VOID_KEY_ENCODER_OPT_KEYPAD_KEY_APPLICATION = 1,

    /** Terminal DEC mode 1035: ignore keypad with numlock (value: bool) */
    VOID_KEY_ENCODER_OPT_IGNORE_KEYPAD_WITH_NUMLOCK = 2,

    /** Terminal DEC mode 1036: alt sends escape prefix (value: bool) */
    VOID_KEY_ENCODER_OPT_ALT_ESC_PREFIX = 3,

    /** xterm modifyOtherKeys mode 2 (value: bool) */
    VOID_KEY_ENCODER_OPT_MODIFY_OTHER_KEYS_STATE_2 = 4,

    /** Kitty keyboard protocol flags (value: VoidKittyKeyFlags bitmask) */
    VOID_KEY_ENCODER_OPT_KITTY_FLAGS = 5,

    /** macOS option-as-alt setting (value: VoidOptionAsAlt) */
    VOID_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT = 6,

    /** Backarrow key mode (value: bool)
     * See https://vt100.net/dec/ek-vt3xx-tp-002.pdf page 170
     * If `false` (the default), `backspace` emits 0x7f
     * If `true`, `backspace` emits 0x08
     */
    VOID_KEY_ENCODER_OPT_BACKARROW_KEY_MODE = 7,

    VOID_KEY_ENCODER_OPT_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidKeyEncoderOption;

/**
 * Create a new key encoder instance.
 *
 * Creates a new key encoder with default options. The encoder can be configured
 * using void_key_encoder_setopt() and must be freed using
 * void_key_encoder_free() when no longer needed.
 *
 * @param allocator Pointer to the allocator to use for memory management, or NULL to use the default allocator
 * @param encoder Pointer to store the created encoder handle
 * @return VOID_SUCCESS on success, or an error code on failure
 *
 * @ingroup key
 */
VOID_API VoidResult void_key_encoder_new(const VoidAllocator *allocator, VoidKeyEncoder *encoder);

/**
 * Free a key encoder instance.
 *
 * Releases all resources associated with the key encoder. After this call,
 * the encoder handle becomes invalid and must not be used.
 *
 * @param encoder The encoder handle to free (may be NULL)
 *
 * @ingroup key
 */
VOID_API void void_key_encoder_free(VoidKeyEncoder encoder);

/**
 * Set an option on the key encoder.
 *
 * Configures the behavior of the key encoder. Options control various aspects
 * of encoding such as terminal modes (cursor key application mode, keypad mode),
 * protocol selection (Kitty keyboard protocol flags), and platform-specific
 * behaviors (macOS option-as-alt).
 *
 * If you are using a terminal instance, you can set the key encoding
 * options based on the active terminal state (e.g. legacy vs Kitty mode
 * and associated flags) with void_key_encoder_setopt_from_terminal().
 *
 * A null pointer value does nothing. It does not reset the value to the
 * default. The setopt call will do nothing.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param option The option to set
 * @param value Pointer to the value to set (type depends on the option)
 *
 * @ingroup key
 */
VOID_API void void_key_encoder_setopt(VoidKeyEncoder encoder, VoidKeyEncoderOption option, const void *value);

/**
 * Set encoder options from a terminal's current state.
 *
 * Reads the terminal's current modes and flags and applies them to the
 * encoder's options. This sets cursor key application mode, keypad mode,
 * alt escape prefix, modifyOtherKeys state, and Kitty keyboard protocol
 * flags from the terminal state.
 *
 * Note that the `macos_option_as_alt` option cannot be determined from
 * terminal state and is reset to `VOID_OPTION_AS_ALT_FALSE` by this
 * call. Use void_key_encoder_setopt() to set it afterward if needed.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param terminal The terminal handle, must not be NULL
 *
 * @ingroup key
 */
VOID_API void void_key_encoder_setopt_from_terminal(VoidKeyEncoder encoder, VoidTerminal terminal);

/**
 * Encode a key event into a terminal escape sequence.
 *
 * Converts a key event into the appropriate terminal escape sequence based on
 * the encoder's current options. The sequence is written to the provided buffer.
 *
 * Not all key events produce output. For example, unmodified modifier keys
 * typically don't generate escape sequences. Check the out_len parameter to
 * determine if any data was written.
 *
 * If the output buffer is too small, this function returns VOID_OUT_OF_SPACE
 * and out_len will contain the required buffer size. The caller can then
 * allocate a larger buffer and call the function again.
 *
 * @param encoder The encoder handle, must not be NULL
 * @param event The key event to encode, must not be NULL
 * @param out_buf Buffer to write the encoded sequence to
 * @param out_buf_size Size of the output buffer in bytes
 * @param out_len Pointer to store the number of bytes written (may be NULL)
 * @return VOID_SUCCESS on success, VOID_OUT_OF_SPACE if buffer too small, or other error code
 *
 * ## Example: Calculate required buffer size
 *
 * @code{.c}
 * // Query the required size with a NULL buffer (always returns OUT_OF_SPACE)
 * size_t required = 0;
 * VoidResult result = void_key_encoder_encode(encoder, event, NULL, 0, &required);
 * assert(result == VOID_OUT_OF_SPACE);
 *
 * // Allocate buffer of required size
 * char *buf = malloc(required);
 *
 * // Encode with properly sized buffer
 * size_t written = 0;
 * result = void_key_encoder_encode(encoder, event, buf, required, &written);
 * assert(result == VOID_SUCCESS);
 *
 * // Use the encoded sequence...
 *
 * free(buf);
 * @endcode
 *
 * ## Example: Direct encoding with static buffer
 *
 * @code{.c}
 * // Most escape sequences are short, so a static buffer often suffices
 * char buf[128];
 * size_t written = 0;
 * VoidResult result = void_key_encoder_encode(encoder, event, buf, sizeof(buf), &written);
 *
 * if (result == VOID_SUCCESS) {
 *   // Write the encoded sequence to the terminal
 *   write(pty_fd, buf, written);
 * } else if (result == VOID_OUT_OF_SPACE) {
 *   // Buffer too small, written contains required size
 *   char *dynamic_buf = malloc(written);
 *   result = void_key_encoder_encode(encoder, event, dynamic_buf, written, &written);
 *   assert(result == VOID_SUCCESS);
 *   write(pty_fd, dynamic_buf, written);
 *   free(dynamic_buf);
 * }
 * @endcode
 *
 * @ingroup key
 */
VOID_API VoidResult void_key_encoder_encode(VoidKeyEncoder encoder, VoidKeyEvent event, char *out_buf, size_t out_buf_size, size_t *out_len);

#endif /* VOID_VT_KEY_ENCODER_H */
