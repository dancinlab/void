#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <void/vt.h>

int main() {
  VoidOscParser parser;
  if (void_osc_new(NULL, &parser) != VOID_SUCCESS) {
    return 1;
  }
  
  // Setup change window title command to change the title to "hello"
  void_osc_next(parser, '0');
  void_osc_next(parser, ';');
  const char *title = "hello";
  for (size_t i = 0; i < strlen(title); i++) {
    void_osc_next(parser, title[i]);
  }
  
  // End parsing and get command
  VoidOscCommand command = void_osc_end(parser, 0);
  
  // Get and print command type
  VoidOscCommandType type = void_osc_command_type(command);
  printf("Command type: %d\n", type);
  
  // Extract and print the title
  if (void_osc_command_data(command, VOID_OSC_DATA_CHANGE_WINDOW_TITLE_STR, &title)) {
    printf("Extracted title: %s\n", title);
  } else {
    printf("Failed to extract title\n");
  }
  
  void_osc_free(parser);
  return 0;
}
