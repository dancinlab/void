#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <void/vt.h>

int main(void) {
  //! [vt-stream-init]
  // Create a terminal
  VoidTerminal terminal;
  VoidTerminalOptions opts = {
    .cols = 80,
    .rows = 24,
    .max_scrollback = 0,
  };
  VoidResult result = void_terminal_new(NULL, &terminal, opts);
  assert(result == VOID_SUCCESS);
  //! [vt-stream-init]

  //! [vt-stream-write]
  // Feed VT data into the terminal
  const char *text = "Hello, World!\r\n";
  void_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // ANSI color codes: ESC[1;32m = bold green, ESC[0m = reset
  text = "\x1b[1;32mGreen Text\x1b[0m\r\n";
  void_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // Cursor positioning: ESC[1;1H = move to row 1, column 1
  text = "\x1b[1;1HTop-left corner\r\n";
  void_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // Cursor movement: ESC[5B = move down 5 lines
  text = "\x1b[5B";
  void_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));
  text = "Moved down!\r\n";
  void_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // Erase line: ESC[2K = clear entire line
  text = "\x1b[2K";
  void_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));
  text = "New content\r\n";
  void_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));

  // Multiple lines
  text = "Line A\r\nLine B\r\nLine C\r\n";
  void_terminal_vt_write(terminal, (const uint8_t *)text, strlen(text));
  //! [vt-stream-write]

  //! [vt-stream-read]
  // Get the final terminal state as a plain string using the formatter
  VoidFormatterTerminalOptions fmt_opts =
      VOID_INIT_SIZED(VoidFormatterTerminalOptions);
  fmt_opts.emit = VOID_FORMATTER_FORMAT_PLAIN;
  fmt_opts.trim = true;

  VoidFormatter formatter;
  result = void_formatter_terminal_new(NULL, &formatter, terminal, fmt_opts);
  assert(result == VOID_SUCCESS);

  uint8_t *buf = NULL;
  size_t len = 0;
  result = void_formatter_format_alloc(formatter, NULL, &buf, &len);
  assert(result == VOID_SUCCESS);

  fwrite(buf, 1, len, stdout);
  printf("\n");

  void_free(NULL, buf, len);
  void_formatter_free(formatter);
  //! [vt-stream-read]

  void_terminal_free(terminal);
  return 0;
}
