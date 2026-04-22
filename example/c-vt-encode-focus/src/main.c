#include <stdio.h>
#include <void/vt.h>

//! [focus-encode]
int main() {
  char buf[8];
  size_t written = 0;

  VoidResult result = void_focus_encode(
      VOID_FOCUS_GAINED, buf, sizeof(buf), &written);

  if (result == VOID_SUCCESS) {
    printf("Encoded %zu bytes: ", written);
    fwrite(buf, 1, written, stdout);
    printf("\n");
  }

  return 0;
}
//! [focus-encode]
