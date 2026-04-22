#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <void/vt.h>

//! [key-encode]
int main() {
  // Create encoder
  VoidKeyEncoder encoder;
  VoidResult result = void_key_encoder_new(NULL, &encoder);
  assert(result == VOID_SUCCESS);

  // Enable Kitty keyboard protocol with all features
  void_key_encoder_setopt(encoder, VOID_KEY_ENCODER_OPT_KITTY_FLAGS,
                             &(uint8_t){VOID_KITTY_KEY_ALL});

  // Create and configure key event for Ctrl+C press
  VoidKeyEvent event;
  result = void_key_event_new(NULL, &event);
  assert(result == VOID_SUCCESS);
  void_key_event_set_action(event, VOID_KEY_ACTION_PRESS);
  void_key_event_set_key(event, VOID_KEY_C);
  void_key_event_set_mods(event, VOID_MODS_CTRL);

  // Encode the key event
  char buf[128];
  size_t written = 0;
  result = void_key_encoder_encode(encoder, event, buf, sizeof(buf), &written);
  assert(result == VOID_SUCCESS);

  // Use the encoded sequence (e.g., write to terminal)
  fwrite(buf, 1, written, stdout);

  // Cleanup
  void_key_event_free(event);
  void_key_encoder_free(encoder);
  return 0;
}
//! [key-encode]
