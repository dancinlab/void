#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <void/vt.h>

//! [mouse-encode]
int main() {
  // Create encoder
  VoidMouseEncoder encoder;
  VoidResult result = void_mouse_encoder_new(NULL, &encoder);
  assert(result == VOID_SUCCESS);

  // Configure SGR format with normal tracking
  void_mouse_encoder_setopt(encoder, VOID_MOUSE_ENCODER_OPT_EVENT,
      &(VoidMouseTrackingMode){VOID_MOUSE_TRACKING_NORMAL});
  void_mouse_encoder_setopt(encoder, VOID_MOUSE_ENCODER_OPT_FORMAT,
      &(VoidMouseFormat){VOID_MOUSE_FORMAT_SGR});

  // Set terminal geometry for coordinate mapping
  void_mouse_encoder_setopt(encoder, VOID_MOUSE_ENCODER_OPT_SIZE,
      &(VoidMouseEncoderSize){
          .size = sizeof(VoidMouseEncoderSize),
          .screen_width = 800, .screen_height = 600,
          .cell_width = 10, .cell_height = 20,
      });

  // Create and configure a left button press event
  VoidMouseEvent event;
  result = void_mouse_event_new(NULL, &event);
  assert(result == VOID_SUCCESS);
  void_mouse_event_set_action(event, VOID_MOUSE_ACTION_PRESS);
  void_mouse_event_set_button(event, VOID_MOUSE_BUTTON_LEFT);
  void_mouse_event_set_position(event,
      (VoidMousePosition){.x = 50.0f, .y = 40.0f});

  // Encode the mouse event
  char buf[128];
  size_t written = 0;
  result = void_mouse_encoder_encode(encoder, event,
      buf, sizeof(buf), &written);
  assert(result == VOID_SUCCESS);

  // Use the encoded sequence (e.g., write to terminal)
  fwrite(buf, 1, written, stdout);

  // Cleanup
  void_mouse_event_free(event);
  void_mouse_encoder_free(encoder);
  return 0;
}
//! [mouse-encode]
