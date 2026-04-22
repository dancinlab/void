#include <stdio.h>
#include <void/vt.h>

//! [modes-pack-unpack]
void modes_example() {
  // Create a mode for DEC mode 25 (cursor visible)
  VoidMode tag = void_mode_new(25, false);
  printf("value=%u ansi=%d packed=0x%04x\n",
      void_mode_value(tag),
      void_mode_ansi(tag),
      tag);

  // Create a mode for ANSI mode 4 (insert mode)
  VoidMode ansi_tag = void_mode_new(4, true);
  printf("value=%u ansi=%d packed=0x%04x\n",
      void_mode_value(ansi_tag),
      void_mode_ansi(ansi_tag),
      ansi_tag);
}
//! [modes-pack-unpack]

//! [modes-decrpm]
void decrpm_example() {
  char buf[32];
  size_t written = 0;

  // Encode a report that DEC mode 25 (cursor visible) is set
  VoidResult result = void_mode_report_encode(
      VOID_MODE_CURSOR_VISIBLE,
      VOID_MODE_REPORT_SET,
      buf, sizeof(buf), &written);

  if (result == VOID_SUCCESS) {
    printf("Encoded %zu bytes: ", written);
    fwrite(buf, 1, written, stdout);
    printf("\n");  // prints: ESC[?25;1$y
  }
}
//! [modes-decrpm]

int main() {
  modes_example();
  decrpm_example();
  return 0;
}
