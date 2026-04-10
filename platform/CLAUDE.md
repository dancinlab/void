# platform/ — OS Abstraction (L1 🟡 Protected)

OS별 FFI + 네이티브 브릿지. 유일한 non-hexa 허용 구역.

common.hexa     크로스플랫폼 스텁
macos.hexa      macOS extern (Cocoa, Metal, CoreText)
void_bridge.m   Objective-C 브릿지 (R1 유일한 예외) — 수정 시 dylib 리빌드

참조: app/main_app.hexa
