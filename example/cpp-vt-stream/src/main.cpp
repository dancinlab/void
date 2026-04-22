#include <cassert>
#include <cstdio>
#include <cstring>
#include <void/vt.h>

int main() {
  // Create a terminal
  VoidTerminal terminal;
  VoidTerminalOptions opts = {
    .cols = 80,
    .rows = 24,
    .max_scrollback = 0,
  };
  VoidResult result = void_terminal_new(nullptr, &terminal, opts);
  assert(result == VOID_SUCCESS);

  // Feed VT data into the terminal
  const char *text = "Hello from C++!\r\n";
  void_terminal_vt_write(terminal, reinterpret_cast<const uint8_t *>(text), std::strlen(text));

  text = "\x1b[1;32mGreen Text\x1b[0m\r\n";
  void_terminal_vt_write(terminal, reinterpret_cast<const uint8_t *>(text), std::strlen(text));

  text = "\x1b[1;1HTop-left corner\r\n";
  void_terminal_vt_write(terminal, reinterpret_cast<const uint8_t *>(text), std::strlen(text));

  // Get the final terminal state as a plain string
  VoidFormatterTerminalOptions fmt_opts =
      VOID_INIT_SIZED(VoidFormatterTerminalOptions);
  fmt_opts.emit = VOID_FORMATTER_FORMAT_PLAIN;
  fmt_opts.trim = true;

  VoidFormatter formatter;
  result = void_formatter_terminal_new(nullptr, &formatter, terminal, fmt_opts);
  assert(result == VOID_SUCCESS);

  uint8_t *buf = nullptr;
  size_t len = 0;
  result = void_formatter_format_alloc(formatter, nullptr, &buf, &len);
  assert(result == VOID_SUCCESS);

  std::fwrite(buf, 1, len, stdout);
  std::printf("\n");

  void_free(nullptr, buf, len);
  void_formatter_free(formatter);
  void_terminal_free(terminal);
  return 0;
}
