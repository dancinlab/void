/**
 * @file event.h
 *
 * Key event representation and manipulation.
 */

#ifndef VOID_VT_KEY_EVENT_H
#define VOID_VT_KEY_EVENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <void/vt/types.h>
#include <void/vt/allocator.h>

/**
 * Opaque handle to a key event.
 * 
 * This handle represents a keyboard input event containing information about
 * the physical key pressed, modifiers, and generated text.
 *
 * @ingroup key
 */
typedef struct VoidKeyEventImpl *VoidKeyEvent;

/**
 * Keyboard input event types.
 *
 * @ingroup key
 */
typedef enum VOID_ENUM_TYPED {
    /** Key was released */
    VOID_KEY_ACTION_RELEASE = 0,
    /** Key was pressed */
    VOID_KEY_ACTION_PRESS = 1,
    /** Key is being repeated (held down) */
    VOID_KEY_ACTION_REPEAT = 2,
    VOID_KEY_ACTION_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidKeyAction;

/**
 * Keyboard modifier keys bitmask.
 *
 * A bitmask representing all keyboard modifiers. This tracks which modifier keys 
 * are pressed and, where supported by the platform, which side (left or right) 
 * of each modifier is active.
 *
 * Use the VOID_MODS_* constants to test and set individual modifiers.
 *
 * Modifier side bits are only meaningful when the corresponding modifier bit is set.
 * Not all platforms support distinguishing between left and right modifier 
 * keys and Void is built to expect that some platforms may not provide this
 * information.
 *
 * @ingroup key
 */
typedef uint16_t VoidMods;

/** Shift key is pressed */
#define VOID_MODS_SHIFT (1 << 0)
/** Control key is pressed */
#define VOID_MODS_CTRL (1 << 1)
/** Alt/Option key is pressed */
#define VOID_MODS_ALT (1 << 2)
/** Super/Command/Windows key is pressed */
#define VOID_MODS_SUPER (1 << 3)
/** Caps Lock is active */
#define VOID_MODS_CAPS_LOCK (1 << 4)
/** Num Lock is active */
#define VOID_MODS_NUM_LOCK (1 << 5)

/**
 * Right shift is pressed (0 = left, 1 = right).
 * Only meaningful when VOID_MODS_SHIFT is set.
 */
#define VOID_MODS_SHIFT_SIDE (1 << 6)
/**
 * Right ctrl is pressed (0 = left, 1 = right).
 * Only meaningful when VOID_MODS_CTRL is set.
 */
#define VOID_MODS_CTRL_SIDE (1 << 7)
/**
 * Right alt is pressed (0 = left, 1 = right).
 * Only meaningful when VOID_MODS_ALT is set.
 */
#define VOID_MODS_ALT_SIDE (1 << 8)
/**
 * Right super is pressed (0 = left, 1 = right).
 * Only meaningful when VOID_MODS_SUPER is set.
 */
#define VOID_MODS_SUPER_SIDE (1 << 9)

/**
 * Physical key codes.
 *
 * The set of key codes that Void is aware of. These represent physical keys 
 * on the keyboard and are layout-independent. For example, the "a" key on a US 
 * keyboard is the same as the "ф" key on a Russian keyboard, but both will 
 * report the same key_a value.
 *
 * Layout-dependent strings are provided separately as UTF-8 text and are produced 
 * by the platform. These values are based on the W3C UI Events KeyboardEvent code 
 * standard. See: https://www.w3.org/TR/uievents-code
 *
 * @ingroup key
 */
typedef enum VOID_ENUM_TYPED {
    VOID_KEY_UNIDENTIFIED = 0,

    // Writing System Keys (W3C § 3.1.1)
    VOID_KEY_BACKQUOTE,
    VOID_KEY_BACKSLASH,
    VOID_KEY_BRACKET_LEFT,
    VOID_KEY_BRACKET_RIGHT,
    VOID_KEY_COMMA,
    VOID_KEY_DIGIT_0,
    VOID_KEY_DIGIT_1,
    VOID_KEY_DIGIT_2,
    VOID_KEY_DIGIT_3,
    VOID_KEY_DIGIT_4,
    VOID_KEY_DIGIT_5,
    VOID_KEY_DIGIT_6,
    VOID_KEY_DIGIT_7,
    VOID_KEY_DIGIT_8,
    VOID_KEY_DIGIT_9,
    VOID_KEY_EQUAL,
    VOID_KEY_INTL_BACKSLASH,
    VOID_KEY_INTL_RO,
    VOID_KEY_INTL_YEN,
    VOID_KEY_A,
    VOID_KEY_B,
    VOID_KEY_C,
    VOID_KEY_D,
    VOID_KEY_E,
    VOID_KEY_F,
    VOID_KEY_G,
    VOID_KEY_H,
    VOID_KEY_I,
    VOID_KEY_J,
    VOID_KEY_K,
    VOID_KEY_L,
    VOID_KEY_M,
    VOID_KEY_N,
    VOID_KEY_O,
    VOID_KEY_P,
    VOID_KEY_Q,
    VOID_KEY_R,
    VOID_KEY_S,
    VOID_KEY_T,
    VOID_KEY_U,
    VOID_KEY_V,
    VOID_KEY_W,
    VOID_KEY_X,
    VOID_KEY_Y,
    VOID_KEY_Z,
    VOID_KEY_MINUS,
    VOID_KEY_PERIOD,
    VOID_KEY_QUOTE,
    VOID_KEY_SEMICOLON,
    VOID_KEY_SLASH,

    // Functional Keys (W3C § 3.1.2)
    VOID_KEY_ALT_LEFT,
    VOID_KEY_ALT_RIGHT,
    VOID_KEY_BACKSPACE,
    VOID_KEY_CAPS_LOCK,
    VOID_KEY_CONTEXT_MENU,
    VOID_KEY_CONTROL_LEFT,
    VOID_KEY_CONTROL_RIGHT,
    VOID_KEY_ENTER,
    VOID_KEY_META_LEFT,
    VOID_KEY_META_RIGHT,
    VOID_KEY_SHIFT_LEFT,
    VOID_KEY_SHIFT_RIGHT,
    VOID_KEY_SPACE,
    VOID_KEY_TAB,
    VOID_KEY_CONVERT,
    VOID_KEY_KANA_MODE,
    VOID_KEY_NON_CONVERT,

    // Control Pad Section (W3C § 3.2)
    VOID_KEY_DELETE,
    VOID_KEY_END,
    VOID_KEY_HELP,
    VOID_KEY_HOME,
    VOID_KEY_INSERT,
    VOID_KEY_PAGE_DOWN,
    VOID_KEY_PAGE_UP,

    // Arrow Pad Section (W3C § 3.3)
    VOID_KEY_ARROW_DOWN,
    VOID_KEY_ARROW_LEFT,
    VOID_KEY_ARROW_RIGHT,
    VOID_KEY_ARROW_UP,

    // Numpad Section (W3C § 3.4)
    VOID_KEY_NUM_LOCK,
    VOID_KEY_NUMPAD_0,
    VOID_KEY_NUMPAD_1,
    VOID_KEY_NUMPAD_2,
    VOID_KEY_NUMPAD_3,
    VOID_KEY_NUMPAD_4,
    VOID_KEY_NUMPAD_5,
    VOID_KEY_NUMPAD_6,
    VOID_KEY_NUMPAD_7,
    VOID_KEY_NUMPAD_8,
    VOID_KEY_NUMPAD_9,
    VOID_KEY_NUMPAD_ADD,
    VOID_KEY_NUMPAD_BACKSPACE,
    VOID_KEY_NUMPAD_CLEAR,
    VOID_KEY_NUMPAD_CLEAR_ENTRY,
    VOID_KEY_NUMPAD_COMMA,
    VOID_KEY_NUMPAD_DECIMAL,
    VOID_KEY_NUMPAD_DIVIDE,
    VOID_KEY_NUMPAD_ENTER,
    VOID_KEY_NUMPAD_EQUAL,
    VOID_KEY_NUMPAD_MEMORY_ADD,
    VOID_KEY_NUMPAD_MEMORY_CLEAR,
    VOID_KEY_NUMPAD_MEMORY_RECALL,
    VOID_KEY_NUMPAD_MEMORY_STORE,
    VOID_KEY_NUMPAD_MEMORY_SUBTRACT,
    VOID_KEY_NUMPAD_MULTIPLY,
    VOID_KEY_NUMPAD_PAREN_LEFT,
    VOID_KEY_NUMPAD_PAREN_RIGHT,
    VOID_KEY_NUMPAD_SUBTRACT,
    VOID_KEY_NUMPAD_SEPARATOR,
    VOID_KEY_NUMPAD_UP,
    VOID_KEY_NUMPAD_DOWN,
    VOID_KEY_NUMPAD_RIGHT,
    VOID_KEY_NUMPAD_LEFT,
    VOID_KEY_NUMPAD_BEGIN,
    VOID_KEY_NUMPAD_HOME,
    VOID_KEY_NUMPAD_END,
    VOID_KEY_NUMPAD_INSERT,
    VOID_KEY_NUMPAD_DELETE,
    VOID_KEY_NUMPAD_PAGE_UP,
    VOID_KEY_NUMPAD_PAGE_DOWN,

    // Function Section (W3C § 3.5)
    VOID_KEY_ESCAPE,
    VOID_KEY_F1,
    VOID_KEY_F2,
    VOID_KEY_F3,
    VOID_KEY_F4,
    VOID_KEY_F5,
    VOID_KEY_F6,
    VOID_KEY_F7,
    VOID_KEY_F8,
    VOID_KEY_F9,
    VOID_KEY_F10,
    VOID_KEY_F11,
    VOID_KEY_F12,
    VOID_KEY_F13,
    VOID_KEY_F14,
    VOID_KEY_F15,
    VOID_KEY_F16,
    VOID_KEY_F17,
    VOID_KEY_F18,
    VOID_KEY_F19,
    VOID_KEY_F20,
    VOID_KEY_F21,
    VOID_KEY_F22,
    VOID_KEY_F23,
    VOID_KEY_F24,
    VOID_KEY_F25,
    VOID_KEY_FN,
    VOID_KEY_FN_LOCK,
    VOID_KEY_PRINT_SCREEN,
    VOID_KEY_SCROLL_LOCK,
    VOID_KEY_PAUSE,

    // Media Keys (W3C § 3.6)
    VOID_KEY_BROWSER_BACK,
    VOID_KEY_BROWSER_FAVORITES,
    VOID_KEY_BROWSER_FORWARD,
    VOID_KEY_BROWSER_HOME,
    VOID_KEY_BROWSER_REFRESH,
    VOID_KEY_BROWSER_SEARCH,
    VOID_KEY_BROWSER_STOP,
    VOID_KEY_EJECT,
    VOID_KEY_LAUNCH_APP_1,
    VOID_KEY_LAUNCH_APP_2,
    VOID_KEY_LAUNCH_MAIL,
    VOID_KEY_MEDIA_PLAY_PAUSE,
    VOID_KEY_MEDIA_SELECT,
    VOID_KEY_MEDIA_STOP,
    VOID_KEY_MEDIA_TRACK_NEXT,
    VOID_KEY_MEDIA_TRACK_PREVIOUS,
    VOID_KEY_POWER,
    VOID_KEY_SLEEP,
    VOID_KEY_AUDIO_VOLUME_DOWN,
    VOID_KEY_AUDIO_VOLUME_MUTE,
    VOID_KEY_AUDIO_VOLUME_UP,
    VOID_KEY_WAKE_UP,

    // Legacy, Non-standard, and Special Keys (W3C § 3.7)
    VOID_KEY_COPY,
    VOID_KEY_CUT,
    VOID_KEY_PASTE,
    VOID_KEY_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidKey;

/**
 * Create a new key event instance.
 * 
 * Creates a new key event with default values. The event must be freed using
 * void_key_event_free() when no longer needed.
 * 
 * @param allocator Pointer to the allocator to use for memory management, or NULL to use the default allocator
 * @param event Pointer to store the created key event handle
 * @return VOID_SUCCESS on success, or an error code on failure
 * 
 * @ingroup key
 */
VOID_API VoidResult void_key_event_new(const VoidAllocator *allocator, VoidKeyEvent *event);

/**
 * Free a key event instance.
 * 
 * Releases all resources associated with the key event. After this call,
 * the event handle becomes invalid and must not be used.
 * 
 * @param event The key event handle to free (may be NULL)
 * 
 * @ingroup key
 */
VOID_API void void_key_event_free(VoidKeyEvent event);

/**
 * Set the key action (press, release, repeat).
 *
 * @param event The key event handle, must not be NULL
 * @param action The action to set
 *
 * @ingroup key
 */
VOID_API void void_key_event_set_action(VoidKeyEvent event, VoidKeyAction action);

/**
 * Get the key action (press, release, repeat).
 *
 * @param event The key event handle, must not be NULL
 * @return The key action
 *
 * @ingroup key
 */
VOID_API VoidKeyAction void_key_event_get_action(VoidKeyEvent event);

/**
 * Set the physical key code.
 *
 * @param event The key event handle, must not be NULL
 * @param key The physical key code to set
 *
 * @ingroup key
 */
VOID_API void void_key_event_set_key(VoidKeyEvent event, VoidKey key);

/**
 * Get the physical key code.
 *
 * @param event The key event handle, must not be NULL
 * @return The physical key code
 *
 * @ingroup key
 */
VOID_API VoidKey void_key_event_get_key(VoidKeyEvent event);

/**
 * Set the modifier keys bitmask.
 *
 * @param event The key event handle, must not be NULL
 * @param mods The modifier keys bitmask to set
 *
 * @ingroup key
 */
VOID_API void void_key_event_set_mods(VoidKeyEvent event, VoidMods mods);

/**
 * Get the modifier keys bitmask.
 *
 * @param event The key event handle, must not be NULL
 * @return The modifier keys bitmask
 *
 * @ingroup key
 */
VOID_API VoidMods void_key_event_get_mods(VoidKeyEvent event);

/**
 * Set the consumed modifiers bitmask.
 *
 * @param event The key event handle, must not be NULL
 * @param consumed_mods The consumed modifiers bitmask to set
 *
 * @ingroup key
 */
VOID_API void void_key_event_set_consumed_mods(VoidKeyEvent event, VoidMods consumed_mods);

/**
 * Get the consumed modifiers bitmask.
 *
 * @param event The key event handle, must not be NULL
 * @return The consumed modifiers bitmask
 *
 * @ingroup key
 */
VOID_API VoidMods void_key_event_get_consumed_mods(VoidKeyEvent event);

/**
 * Set whether the key event is part of a composition sequence.
 *
 * @param event The key event handle, must not be NULL
 * @param composing Whether the key event is part of a composition sequence
 *
 * @ingroup key
 */
VOID_API void void_key_event_set_composing(VoidKeyEvent event, bool composing);

/**
 * Get whether the key event is part of a composition sequence.
 *
 * @param event The key event handle, must not be NULL
 * @return Whether the key event is part of a composition sequence
 *
 * @ingroup key
 */
VOID_API bool void_key_event_get_composing(VoidKeyEvent event);

/**
 * Set the UTF-8 text generated by the key for the current keyboard layout.
 *
 * Must contain the unmodified character before any Ctrl/Meta transformations.
 * The encoder derives modifier sequences from the logical key and mods
 * bitmask, not from this text. Do not pass C0 control characters
 * (U+0000-U+001F, U+007F) or platform function key codes (e.g. macOS PUA
 * U+F700-U+F8FF); pass NULL instead and let the encoder use the logical key.
 *
 * The key event does NOT take ownership of the text pointer. The caller
 * must ensure the string remains valid for the lifetime needed by the event.
 *
 * @param event The key event handle, must not be NULL
 * @param utf8 The UTF-8 text to set (or NULL for empty)
 * @param len Length of the UTF-8 text in bytes
 *
 * @ingroup key
 */
VOID_API void void_key_event_set_utf8(VoidKeyEvent event, const char *utf8, size_t len);

/**
 * Get the UTF-8 text generated by the key event.
 *
 * The returned pointer is valid until the event is freed or the UTF-8 text is modified.
 *
 * @param event The key event handle, must not be NULL
 * @param len Pointer to store the length of the UTF-8 text in bytes (may be NULL)
 * @return The UTF-8 text (or NULL for empty)
 *
 * @ingroup key
 */
VOID_API const char *void_key_event_get_utf8(VoidKeyEvent event, size_t *len);

/**
 * Set the unshifted Unicode codepoint.
 *
 * @param event The key event handle, must not be NULL
 * @param codepoint The unshifted Unicode codepoint to set
 *
 * @ingroup key
 */
VOID_API void void_key_event_set_unshifted_codepoint(VoidKeyEvent event, uint32_t codepoint);

/**
 * Get the unshifted Unicode codepoint.
 *
 * @param event The key event handle, must not be NULL
 * @return The unshifted Unicode codepoint
 *
 * @ingroup key
 */
VOID_API uint32_t void_key_event_get_unshifted_codepoint(VoidKeyEvent event);

#endif /* VOID_VT_KEY_EVENT_H */
