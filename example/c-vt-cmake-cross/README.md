# c-vt-cmake-cross

Demonstrates using `void_vt_add_target()` to cross-compile
libvoid-vt with static linking. The target OS is chosen automatically:

| Host    | Target          |
| ------- | --------------- |
| Linux   | Windows (MinGW) |
| Windows | Linux (glibc)   |
| macOS   | Linux (glibc)   |

Override with `-DZIG_TARGET=...` if needed.

## Building

```shell-session
cd example/c-vt-cmake-cross
cmake -B build -DFETCHCONTENT_SOURCE_DIR_VOID=../..
cmake --build build
file build/c_vt_cmake_cross
```
