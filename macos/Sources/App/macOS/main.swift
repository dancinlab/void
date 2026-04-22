import AppKit
import Cocoa
import VoidKit

// Initialize Void global state. We do this once right away because the
// CLI APIs require it and it lets us ensure it is done immediately for the
// rest of the app.
if void_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != VOID_SUCCESS {
    Void.logger.critical("void_init failed")

    // We also write to stderr if this is executed from the CLI or zig run
    switch Void.launchSource {
    case .cli, .zig_run:
        let stderrHandle = FileHandle.standardError
        stderrHandle.write(
            "Void failed to initialize! If you're executing Void from the command line\n" +
            "then this is usually because an invalid action or multiple actions were specified.\n" +
            "Actions start with the `+` character.\n\n" +
            "View all available actions by running `void +help`.\n")
        exit(1)

    case .app:
        // For the app we exit immediately. We should handle this case more
        // gracefully in the future.
        exit(1)
    }
}

// This will run the CLI action and exit if one was specified. A CLI
// action is a command starting with a `+`, such as `void +boo`.
void_cli_try_action()

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
