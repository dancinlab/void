import Foundation
import VoidVt

// Create a terminal with a small grid
var terminal: VoidTerminal?
var opts = VoidTerminalOptions(
    cols: 80,
    rows: 24,
    max_scrollback: 0
)
let result = void_terminal_new(nil, &terminal, opts)
guard result == VOID_SUCCESS, let terminal else {
    fatalError("Failed to create terminal")
}

// Write some VT-encoded content
let text = "Hello from \u{1b}[1mSwift\u{1b}[0m via xcframework!\r\n"
text.withCString { ptr in
    void_terminal_vt_write(terminal, ptr, strlen(ptr))
}

// Format the terminal contents as plain text
var fmtOpts = VoidFormatterTerminalOptions()
fmtOpts.size = MemoryLayout<VoidFormatterTerminalOptions>.size
fmtOpts.emit = VOID_FORMATTER_FORMAT_PLAIN
fmtOpts.trim = true

var formatter: VoidFormatter?
let fmtResult = void_formatter_terminal_new(nil, &formatter, terminal, fmtOpts)
guard fmtResult == VOID_SUCCESS, let formatter else {
    fatalError("Failed to create formatter")
}

var buf: UnsafeMutablePointer<UInt8>?
var len: Int = 0
let allocResult = void_formatter_format_alloc(formatter, nil, &buf, &len)
guard allocResult == VOID_SUCCESS, let buf else {
    fatalError("Failed to format")
}

print("Plain text (\(len) bytes):")
let data = Data(bytes: buf, count: len)
print(String(data: data, encoding: .utf8) ?? "<invalid UTF-8>")

void_free(nil, buf, len)
void_formatter_free(formatter)
void_terminal_free(terminal)
