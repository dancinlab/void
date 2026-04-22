# Example: `void-vt` Terminal Formatter

This contains a simple example of how to use the `void-vt` terminal and
formatter APIs to create a terminal, write VT-encoded content into it, and
format the screen contents as plain text.

This uses a `build.zig` and `Zig` to build the C program so that we
can reuse a lot of our build logic and depend directly on our source
tree, but Void emits a standard C library that can be used with any
C tooling.

## Usage

Run the program:

```shell-session
zig build run
```
