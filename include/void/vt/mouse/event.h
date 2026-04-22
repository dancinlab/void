/**
 * @file event.h
 *
 * Mouse event representation and manipulation.
 */

#ifndef VOID_VT_MOUSE_EVENT_H
#define VOID_VT_MOUSE_EVENT_H

#include <stdbool.h>
#include <void/vt/allocator.h>
#include <void/vt/key/event.h>
#include <void/vt/types.h>

/**
 * Opaque handle to a mouse event.
 *
 * This handle represents a normalized mouse input event containing
 * action, button, modifiers, and surface-space position.
 *
 * @ingroup mouse
 */
typedef struct VoidMouseEventImpl *VoidMouseEvent;

/**
 * Mouse event action type.
 *
 * @ingroup mouse
 */
typedef enum VOID_ENUM_TYPED {
  /** Mouse button was pressed. */
  VOID_MOUSE_ACTION_PRESS = 0,

  /** Mouse button was released. */
  VOID_MOUSE_ACTION_RELEASE = 1,

  /** Mouse moved. */
  VOID_MOUSE_ACTION_MOTION = 2,
  VOID_MOUSE_ACTION_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidMouseAction;

/**
 * Mouse button identity.
 *
 * @ingroup mouse
 */
typedef enum VOID_ENUM_TYPED {
  VOID_MOUSE_BUTTON_UNKNOWN = 0,
  VOID_MOUSE_BUTTON_LEFT = 1,
  VOID_MOUSE_BUTTON_RIGHT = 2,
  VOID_MOUSE_BUTTON_MIDDLE = 3,
  VOID_MOUSE_BUTTON_FOUR = 4,
  VOID_MOUSE_BUTTON_FIVE = 5,
  VOID_MOUSE_BUTTON_SIX = 6,
  VOID_MOUSE_BUTTON_SEVEN = 7,
  VOID_MOUSE_BUTTON_EIGHT = 8,
  VOID_MOUSE_BUTTON_NINE = 9,
  VOID_MOUSE_BUTTON_TEN = 10,
  VOID_MOUSE_BUTTON_ELEVEN = 11,
  VOID_MOUSE_BUTTON_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidMouseButton;

/**
 * Mouse position in surface-space pixels.
 *
 * @ingroup mouse
 */
typedef struct {
  float x;
  float y;
} VoidMousePosition;

/**
 * Create a new mouse event instance.
 *
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param event Pointer to store the created event handle
 * @return VOID_SUCCESS on success, or an error code on failure
 *
 * @ingroup mouse
 */
VOID_API VoidResult void_mouse_event_new(const VoidAllocator *allocator,
                                      VoidMouseEvent *event);

/**
 * Free a mouse event instance.
 *
 * @param event The mouse event handle to free (may be NULL)
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_event_free(VoidMouseEvent event);

/**
 * Set the event action.
 *
 * @param event The event handle, must not be NULL
 * @param action The action to set
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_event_set_action(VoidMouseEvent event,
                                    VoidMouseAction action);

/**
 * Get the event action.
 *
 * @param event The event handle, must not be NULL
 * @return The event action
 *
 * @ingroup mouse
 */
VOID_API VoidMouseAction void_mouse_event_get_action(VoidMouseEvent event);

/**
 * Set the event button.
 *
 * This sets a concrete button identity for the event.
 * To represent "no button" (for motion events), use
 * void_mouse_event_clear_button().
 *
 * @param event The event handle, must not be NULL
 * @param button The button to set
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_event_set_button(VoidMouseEvent event,
                                    VoidMouseButton button);

/**
 * Clear the event button.
 *
 * This sets the event button to "none".
 *
 * @param event The event handle, must not be NULL
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_event_clear_button(VoidMouseEvent event);

/**
 * Get the event button.
 *
 * @param event The event handle, must not be NULL
 * @param out_button Output pointer for the button value (may be NULL)
 * @return true if a button is set, false if no button is set
 *
 * @ingroup mouse
 */
VOID_API bool void_mouse_event_get_button(VoidMouseEvent event,
                                    VoidMouseButton *out_button);

/**
 * Set keyboard modifiers held during the event.
 *
 * @param event The event handle, must not be NULL
 * @param mods Modifier bitmask
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_event_set_mods(VoidMouseEvent event,
                                  VoidMods mods);

/**
 * Get keyboard modifiers held during the event.
 *
 * @param event The event handle, must not be NULL
 * @return Modifier bitmask
 *
 * @ingroup mouse
 */
VOID_API VoidMods void_mouse_event_get_mods(VoidMouseEvent event);

/**
 * Set the event position in surface-space pixels.
 *
 * @param event The event handle, must not be NULL
 * @param position The position to set
 *
 * @ingroup mouse
 */
VOID_API void void_mouse_event_set_position(VoidMouseEvent event,
                                      VoidMousePosition position);

/**
 * Get the event position in surface-space pixels.
 *
 * @param event The event handle, must not be NULL
 * @return The current event position
 *
 * @ingroup mouse
 */
VOID_API VoidMousePosition void_mouse_event_get_position(VoidMouseEvent event);

#endif /* VOID_VT_MOUSE_EVENT_H */
