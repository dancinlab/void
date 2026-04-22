#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <void/vt.h>

//! [colors-set-defaults]
/// Set up a dark color theme with custom palette entries.
void set_color_theme(VoidTerminal terminal) {
  // Set default foreground (light gray) and background (dark)
  VoidColorRgb fg = { .r = 0xDD, .g = 0xDD, .b = 0xDD };
  VoidColorRgb bg = { .r = 0x1E, .g = 0x1E, .b = 0x2E };
  VoidColorRgb cursor = { .r = 0xF5, .g = 0xE0, .b = 0xDC };

  void_terminal_set(terminal, VOID_TERMINAL_OPT_COLOR_FOREGROUND, &fg);
  void_terminal_set(terminal, VOID_TERMINAL_OPT_COLOR_BACKGROUND, &bg);
  void_terminal_set(terminal, VOID_TERMINAL_OPT_COLOR_CURSOR, &cursor);

  // Set a custom palette — start from the built-in default and override
  // the first 8 entries with a custom dark theme.
  VoidColorRgb palette[256];
  void_terminal_get(terminal, VOID_TERMINAL_DATA_COLOR_PALETTE, palette);

  palette[VOID_COLOR_NAMED_BLACK]   = (VoidColorRgb){ 0x45, 0x47, 0x5A };
  palette[VOID_COLOR_NAMED_RED]     = (VoidColorRgb){ 0xF3, 0x8B, 0xA8 };
  palette[VOID_COLOR_NAMED_GREEN]   = (VoidColorRgb){ 0xA6, 0xE3, 0xA1 };
  palette[VOID_COLOR_NAMED_YELLOW]  = (VoidColorRgb){ 0xF9, 0xE2, 0xAF };
  palette[VOID_COLOR_NAMED_BLUE]    = (VoidColorRgb){ 0x89, 0xB4, 0xFA };
  palette[VOID_COLOR_NAMED_MAGENTA] = (VoidColorRgb){ 0xF5, 0xC2, 0xE7 };
  palette[VOID_COLOR_NAMED_CYAN]    = (VoidColorRgb){ 0x94, 0xE2, 0xD5 };
  palette[VOID_COLOR_NAMED_WHITE]   = (VoidColorRgb){ 0xBA, 0xC2, 0xDE };

  void_terminal_set(terminal, VOID_TERMINAL_OPT_COLOR_PALETTE, palette);
}
//! [colors-set-defaults]

//! [colors-read]
/// Print the effective and default values for a color, showing how
/// OSC overrides layer on top of defaults.
void print_color(VoidTerminal terminal,
                 const char* name,
                 VoidTerminalData effective_data,
                 VoidTerminalData default_data) {
  VoidColorRgb color;

  VoidResult res = void_terminal_get(terminal, effective_data, &color);
  if (res == VOID_SUCCESS) {
    printf("  %-12s effective: #%02X%02X%02X", name, color.r, color.g, color.b);
  } else {
    printf("  %-12s effective: (not set)", name);
  }

  res = void_terminal_get(terminal, default_data, &color);
  if (res == VOID_SUCCESS) {
    printf("  default: #%02X%02X%02X\n", color.r, color.g, color.b);
  } else {
    printf("  default: (not set)\n");
  }
}

void print_all_colors(VoidTerminal terminal, const char* label) {
  printf("%s:\n", label);
  print_color(terminal, "foreground",
      VOID_TERMINAL_DATA_COLOR_FOREGROUND,
      VOID_TERMINAL_DATA_COLOR_FOREGROUND_DEFAULT);
  print_color(terminal, "background",
      VOID_TERMINAL_DATA_COLOR_BACKGROUND,
      VOID_TERMINAL_DATA_COLOR_BACKGROUND_DEFAULT);
  print_color(terminal, "cursor",
      VOID_TERMINAL_DATA_COLOR_CURSOR,
      VOID_TERMINAL_DATA_COLOR_CURSOR_DEFAULT);

  // Show palette index 0 (black) as an example
  VoidColorRgb palette[256];
  void_terminal_get(terminal, VOID_TERMINAL_DATA_COLOR_PALETTE, palette);
  printf("  %-12s effective: #%02X%02X%02X", "palette[0]",
      palette[0].r, palette[0].g, palette[0].b);

  void_terminal_get(terminal, VOID_TERMINAL_DATA_COLOR_PALETTE_DEFAULT,
      palette);
  printf("  default: #%02X%02X%02X\n", palette[0].r, palette[0].g, palette[0].b);
}
//! [colors-read]

//! [colors-main]
int main() {
  // Create a terminal
  VoidTerminal terminal = NULL;
  VoidTerminalOptions opts = {
    .cols = 80,
    .rows = 24,
    .max_scrollback = 0,
  };
  if (void_terminal_new(NULL, &terminal, opts) != VOID_SUCCESS) {
    fprintf(stderr, "Failed to create terminal\n");
    return 1;
  }

  // Before setting any colors, everything is unset
  print_all_colors(terminal, "Before setting defaults");

  // Set our color theme defaults
  set_color_theme(terminal);
  print_all_colors(terminal, "\nAfter setting defaults");

  // Simulate an OSC override (e.g. a program running inside the
  // terminal changes the foreground via OSC 10)
  const char* osc_fg = "\x1B]10;rgb:FF/00/00\x1B\\";
  void_terminal_vt_write(terminal, (const uint8_t*)osc_fg,
                            strlen(osc_fg));
  print_all_colors(terminal, "\nAfter OSC foreground override");

  // Clear the foreground default — the OSC override is still active
  void_terminal_set(terminal, VOID_TERMINAL_OPT_COLOR_FOREGROUND, NULL);
  print_all_colors(terminal, "\nAfter clearing foreground default");

  void_terminal_free(terminal);
  return 0;
}
//! [colors-main]
