# macOS Void Application

- Use `swiftlint` for formatting and linting Swift code.
- If code outside of `macos/` directory is modified, use
  `zig build -Demit-macos-app=false` before building the macOS app to update
  the underlying Void library.
- Use `macos/build.nu` to build the macOS app, do not use `zig build`
  (except to build the underlying library as mentioned above).
  - Build: `macos/build.nu [--scheme Void] [--configuration Debug] [--action build]`
  - Output: `macos/build/<configuration>/Void.app` (e.g. `macos/build/Debug/Void.app`)
- Run unit tests directly with `macos/build.nu --action test`

## Local iteration vs public release

For day-to-day changes, **do NOT run `hx install` / `install.hexa`** — it does
a full clean ReleaseFast build + stable-identity codesign + TCC reset + Full
Disk Access prompt, which is the right thing only for a public-distribution
install. For local edits, prefer the much faster cycle:

```sh
# from repo root — incremental build + drop into /Applications.
vendor/zig-0.15.2/bin/zig build -Demit-macos-app -Doptimize=ReleaseFast
osascript -e 'tell application "Void" to quit' 2>/dev/null
pkill -x void 2>/dev/null
rm -rf /Applications/Void.app.new
cp -R macos/build/ReleaseLocal/Void.app /Applications/Void.app.new
rm -rf /Applications/Void.app
mv /Applications/Void.app.new /Applications/Void.app
open -a /Applications/Void.app
```

Run the installed binary directly when you need to exercise it from a script:
`/Applications/Void.app/Contents/MacOS/void` — that path is the canonical
artifact and should be used over the `build/ReleaseLocal/` copy once an
install is done.

Reserve `hx install` for **public-release** builds where the TCC permission
persistence and codesign identity rotation actually matter.

## AppleScript

- The AppleScript scripting definition is in `macos/Void.sdef`.
- Guard AppleScript entry points and object accessors with the
  `macos-applescript` configuration (use `NSApp.isAppleScriptEnabled`
  and `NSApp.validateScript(command:)` where applicable).
- In `macos/Void.sdef`, keep top-level definitions in this order:
  1. Classes
  2. Records
  3. Enums
  4. Commands
- Test AppleScript support:
  (1) Build with `macos/build.nu`
  (2) Launch and activate the app via osascript using the absolute path
      to the built app bundle:
      `osascript -e 'tell application "<absolute path to build/Debug/Void.app>" to activate'`
  (3) Wait a few seconds for the app to fully launch and open a terminal.
  (4) Run test scripts with `osascript`, always targeting the app by
      its absolute path (not by name) to avoid calling the wrong
      application.
  (5) When done, quit via:
      `osascript -e 'tell application "<absolute path to build/Debug/Void.app>" to quit'`
