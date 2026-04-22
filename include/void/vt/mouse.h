/**
 * @file mouse.h
 *
 * Mouse encoding module - encode mouse events into terminal escape sequences.
 */

#ifndef VOID_VT_MOUSE_H
#define VOID_VT_MOUSE_H

/** @defgroup mouse Mouse Encoding
 *
 * Utilities for encoding mouse events into terminal escape sequences,
 * supporting X10, UTF-8, SGR, URxvt, and SGR-Pixels mouse protocols.
 *
 * ## Basic Usage
 *
 * 1. Create an encoder instance with void_mouse_encoder_new().
 * 2. Configure encoder options with void_mouse_encoder_setopt() or
 *    void_mouse_encoder_setopt_from_terminal().
 * 3. For each mouse event:
 *    - Create a mouse event with void_mouse_event_new().
 *    - Set event properties (action, button, modifiers, position).
 *    - Encode with void_mouse_encoder_encode().
 *    - Free the event with void_mouse_event_free() or reuse it.
 * 4. Free the encoder with void_mouse_encoder_free() when done.
 *
 * For a complete working example, see example/c-vt-encode-mouse in the
 * repository.
 *
 * ## Example
 *
 * @snippet c-vt-encode-mouse/src/main.c mouse-encode
 *
 * ## Example: Encoding with Terminal State
 *
 * When you have a VoidTerminal, you can sync its tracking mode and
 * output format into the encoder automatically:
 *
 * @code{.c}
 * // Create a terminal and feed it some VT data that enables mouse tracking
 * VoidTerminal terminal;
 * void_terminal_new(NULL, &terminal,
 *     (VoidTerminalOptions){.cols = 80, .rows = 24, .max_scrollback = 0});
 *
 * // Application might write data that enables mouse reporting, etc.
 * void_terminal_vt_write(terminal, vt_data, vt_len);
 *
 * // Create an encoder and sync its options from the terminal
 * VoidMouseEncoder encoder;
 * void_mouse_encoder_new(NULL, &encoder);
 * void_mouse_encoder_setopt_from_terminal(encoder, terminal);
 *
 * // Encode a mouse event using the terminal-derived options
 * char buf[128];
 * size_t written = 0;
 * void_mouse_encoder_encode(encoder, event, buf, sizeof(buf), &written);
 *
 * void_mouse_encoder_free(encoder);
 * void_terminal_free(terminal);
 * @endcode
 *
 * @{
 */

#include <void/vt/mouse/event.h>
#include <void/vt/mouse/encoder.h>

/** @} */

#endif /* VOID_VT_MOUSE_H */
