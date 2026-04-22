import os
import SwiftUI
import VoidKit

// MARK: C Extensions

/// A command is fully self-contained so it is Sendable.
extension void_command_s: @unchecked @retroactive Sendable {}

/// A surface is sendable because it is just a reference type. Using the surface in parameters
/// may be unsafe but the value itself is safe to send across threads.
extension void_surface_t: @unchecked @retroactive Sendable {}

extension Void {
    // The user notification category identifier
    static let userNotificationCategory = "com.mitchellh.void.userNotification"

    // The user notification "Show" action
    static let userNotificationActionShow = "com.mitchellh.void.userNotification.Show"
}

// MARK: Build Info

extension Void {
    struct Info {
        var mode: void_build_mode_e
        var version: String
    }

    static var info: Info {
        let raw = void_info()
        let version = NSString(
            bytes: raw.version,
            length: Int(raw.version_len),
            encoding: NSUTF8StringEncoding
        ) ?? "unknown"

        return Info(mode: raw.build_mode, version: String(version))
    }
}

// MARK: General Helpers

extension Void {
    enum LaunchSource: String {
        case cli
        case app
        case zig_run
    }

    /// Returns the mechanism that launched the app. This is based on an env var so
    /// its up to the env var being set in the correct circumstance.
    static var launchSource: LaunchSource {
        guard let envValue = ProcessInfo.processInfo.environment["VOID_MAC_LAUNCH_SOURCE"] else {
            // We default to the CLI because the app bundle always sets the
            // source. If its unset we assume we're in a CLI environment.
            return .cli
        }

        // If the env var is set but its unknown then we default back to the app.
        return LaunchSource(rawValue: envValue) ?? .app
    }
}

// MARK: Swift Types for C Types

extension Void {
    class AllocatedString {
        private let cString: void_string_s

        init(_ c: void_string_s) {
            self.cString = c
        }

        var string: String {
            guard let ptr = cString.ptr else { return "" }
            let data = Data(bytes: ptr, count: Int(cString.len))
            return String(data: data, encoding: .utf8) ?? ""
        }

        deinit {
            void_string_free(cString)
        }
    }
}

extension Void {
    enum SetFloatWIndow {
        case on
        case off
        case toggle

        static func from(_ c: void_action_float_window_e) -> Self? {
            switch c {
            case VOID_FLOAT_WINDOW_ON:
                return .on

            case VOID_FLOAT_WINDOW_OFF:
                return .off

            case VOID_FLOAT_WINDOW_TOGGLE:
                return .toggle

            default:
                return nil
            }
        }
    }

    enum SetSecureInput {
        case on
        case off
        case toggle

        static func from(_ c: void_action_secure_input_e) -> Self? {
            switch c {
            case VOID_SECURE_INPUT_ON:
                return .on

            case VOID_SECURE_INPUT_OFF:
                return .off

            case VOID_SECURE_INPUT_TOGGLE:
                return .toggle

            default:
                return nil
            }
        }
    }

    /// An enum that is used for the directions that a split focus event can change.
    enum SplitFocusDirection {
        case previous, next, up, down, left, right

        /// Initialize from a Void API enum.
        static func from(direction: void_action_goto_split_e) -> Self? {
            switch direction {
            case VOID_GOTO_SPLIT_PREVIOUS:
                return .previous

            case VOID_GOTO_SPLIT_NEXT:
                return .next

            case VOID_GOTO_SPLIT_UP:
                return .up

            case VOID_GOTO_SPLIT_DOWN:
                return .down

            case VOID_GOTO_SPLIT_LEFT:
                return .left

            case VOID_GOTO_SPLIT_RIGHT:
                return .right

            default:
                return nil
            }
        }

        func toNative() -> void_action_goto_split_e {
            switch self {
            case .previous:
                return VOID_GOTO_SPLIT_PREVIOUS

            case .next:
                return VOID_GOTO_SPLIT_NEXT

            case .up:
                return VOID_GOTO_SPLIT_UP

            case .down:
                return VOID_GOTO_SPLIT_DOWN

            case .left:
                return VOID_GOTO_SPLIT_LEFT

            case .right:
                return VOID_GOTO_SPLIT_RIGHT
            }
        }
    }

    /// Enum used for resizing splits. This is the direction the split divider will move.
    enum SplitResizeDirection {
        case up, down, left, right

        static func from(direction: void_action_resize_split_direction_e) -> Self? {
            switch direction {
            case VOID_RESIZE_SPLIT_UP:
                return .up
            case VOID_RESIZE_SPLIT_DOWN:
                return .down
            case VOID_RESIZE_SPLIT_LEFT:
                return .left
            case VOID_RESIZE_SPLIT_RIGHT:
                return .right
            default:
                return nil
            }
        }

        func toNative() -> void_action_resize_split_direction_e {
            switch self {
            case .up:
                return VOID_RESIZE_SPLIT_UP
            case .down:
                return VOID_RESIZE_SPLIT_DOWN
            case .left:
                return VOID_RESIZE_SPLIT_LEFT
            case .right:
                return VOID_RESIZE_SPLIT_RIGHT
            }
        }
    }
}

#if canImport(AppKit)
// MARK: SplitFocusDirection Extensions

extension Void.SplitFocusDirection {
    /// Convert to a SplitTree.FocusDirection for the given ViewType.
    func toSplitTreeFocusDirection<ViewType>() -> SplitTree<ViewType>.FocusDirection {
        switch self {
        case .previous:
            return .previous

        case .next:
            return .next

        case .up:
            return .spatial(.up)

        case .down:
            return .spatial(.down)

        case .left:
            return .spatial(.left)

        case .right:
            return .spatial(.right)
        }
    }
}
#endif

extension Void {
    /// The type of a clipboard request
    enum ClipboardRequest {
        /// A direct paste of clipboard contents
        case paste

        /// An application is attempting to read from the clipboard using OSC 52
        case osc_52_read

        /// An application is attempting to write to the clipboard using OSC 52
        case osc_52_write(OSPasteboard?)

        /// The text to show in the clipboard confirmation prompt for a given request type
        func text() -> String {
            switch self {
            case .paste:
                return """
                Pasting this text to the terminal may be dangerous as it looks like some commands may be executed.
                """
            case .osc_52_read:
                return """
                An application is attempting to read from the clipboard.
                The current clipboard contents are shown below.
                """
            case .osc_52_write:
                return """
                An application is attempting to write to the clipboard.
                The content to write is shown below.
                """
            }
        }

        static func from(request: void_clipboard_request_e) -> ClipboardRequest? {
            switch request {
            case VOID_CLIPBOARD_REQUEST_PASTE:
                return .paste
            case VOID_CLIPBOARD_REQUEST_OSC_52_READ:
                return .osc_52_read
            case VOID_CLIPBOARD_REQUEST_OSC_52_WRITE:
                return .osc_52_write(nil)
            default:
                return nil
            }
        }
    }

    struct ClipboardContent {
        let mime: String
        let data: String

        static func from(content: void_clipboard_content_s) -> ClipboardContent? {
            guard let mimePtr = content.mime,
                  let dataPtr = content.data else {
                return nil
            }

            return ClipboardContent(
                mime: String(cString: mimePtr),
                data: String(cString: dataPtr)
            )
        }
    }

    /// Enum for the macos-window-buttons config option
    enum MacOSWindowButtons: String {
        case visible
        case hidden
    }

    /// Enum for the macos-titlebar-proxy-icon config option
    enum MacOSTitlebarProxyIcon: String {
        case visible
        case hidden
    }

    /// Enum for auto-update-channel config option
    enum AutoUpdateChannel: String {
        case tip
        case stable
    }
}

// MARK: Surface Notification

extension Notification.Name {
    /// Configuration change. If the object is nil then it is app-wide. Otherwise its surface-specific.
    static let voidConfigDidChange = Notification.Name("com.mitchellh.void.configDidChange")
    static let VoidConfigChangeKey = voidConfigDidChange.rawValue

    /// Color change. Object is the surface changing.
    static let voidColorDidChange = Notification.Name("com.mitchellh.void.voidColorDidChange")
    static let VoidColorChangeKey = voidColorDidChange.rawValue

    /// Goto tab. Has tab index in the userinfo.
    static let voidMoveTab = Notification.Name("com.mitchellh.void.moveTab")
    static let VoidMoveTabKey = voidMoveTab.rawValue

    /// Close tab
    static let voidCloseTab = Notification.Name("com.mitchellh.void.closeTab")

    /// Close other tabs
    static let voidCloseOtherTabs = Notification.Name("com.mitchellh.void.closeOtherTabs")

    /// Close tabs to the right of the focused tab
    static let voidCloseTabsOnTheRight = Notification.Name("com.mitchellh.void.closeTabsOnTheRight")

    /// Close window
    static let voidCloseWindow = Notification.Name("com.mitchellh.void.closeWindow")

    /// Resize the window to a default size.
    static let voidResetWindowSize = Notification.Name("com.mitchellh.void.resetWindowSize")

    /// Ring the bell
    static let voidBellDidRing = Notification.Name("com.mitchellh.void.voidBellDidRing")

    /// Readonly mode changed
    static let voidDidChangeReadonly = Notification.Name("com.mitchellh.void.didChangeReadonly")
    static let ReadonlyKey = voidDidChangeReadonly.rawValue + ".readonly"
    static let voidCommandPaletteDidToggle = Notification.Name("com.mitchellh.void.commandPaletteDidToggle")

    /// Toggle maximize of current window
    static let voidMaximizeDidToggle = Notification.Name("com.mitchellh.void.maximizeDidToggle")

    /// Notification sent when scrollbar updates
    static let voidDidUpdateScrollbar = Notification.Name("com.mitchellh.void.didUpdateScrollbar")
    static let ScrollbarKey = voidDidUpdateScrollbar.rawValue + ".scrollbar"

    /// Focus the search field
    static let voidSearchFocus = Notification.Name("com.mitchellh.void.searchFocus")
}

// NOTE: I am moving all of these to Notification.Name extensions over time. This
// namespace was the old namespace.
extension Void.Notification {
    /// Used to pass a configuration along when creating a new tab/window/split.
    static let NewSurfaceConfigKey = "com.mitchellh.void.newSurfaceConfig"

    /// Posted when a new split is requested. The sending object will be the surface that had focus. The
    /// userdata has one key "direction" with the direction to split to.
    static let voidNewSplit = Notification.Name("com.mitchellh.void.newSplit")

    /// Close the calling surface.
    static let voidCloseSurface = Notification.Name("com.mitchellh.void.closeSurface")

    /// Focus previous/next split. Has a SplitFocusDirection in the userinfo.
    static let voidFocusSplit = Notification.Name("com.mitchellh.void.focusSplit")
    static let SplitDirectionKey = voidFocusSplit.rawValue

    /// Goto tab. Has tab index in the userinfo.
    static let voidGotoTab = Notification.Name("com.mitchellh.void.gotoTab")
    static let GotoTabKey = voidGotoTab.rawValue

    /// New tab. Has base surface config requested in userinfo.
    static let voidNewTab = Notification.Name("com.mitchellh.void.newTab")

    /// New window. Has base surface config requested in userinfo.
    static let voidNewWindow = Notification.Name("com.mitchellh.void.newWindow")

    /// Present terminal. Bring the surface's window to focus without activating the app.
    static let voidPresentTerminal = Notification.Name("com.mitchellh.void.presentTerminal")

    /// Toggle fullscreen of current window
    static let voidToggleFullscreen = Notification.Name("com.mitchellh.void.toggleFullscreen")
    static let FullscreenModeKey = voidToggleFullscreen.rawValue

    /// Notification sent to toggle split maximize/unmaximize.
    static let didToggleSplitZoom = Notification.Name("com.mitchellh.void.didToggleSplitZoom")

    /// Notification
    static let didReceiveInitialWindowFrame = Notification.Name("com.mitchellh.void.didReceiveInitialWindowFrame")
    static let FrameKey = "com.mitchellh.void.frame"

    /// Notification to render the inspector for a surface
    static let inspectorNeedsDisplay = Notification.Name("com.mitchellh.void.inspectorNeedsDisplay")

    /// Notification to show/hide the inspector
    static let didControlInspector = Notification.Name("com.mitchellh.void.didControlInspector")

    static let confirmClipboard = Notification.Name("com.mitchellh.void.confirmClipboard")
    static let ConfirmClipboardStrKey = confirmClipboard.rawValue + ".str"
    static let ConfirmClipboardStateKey = confirmClipboard.rawValue + ".state"
    static let ConfirmClipboardRequestKey = confirmClipboard.rawValue + ".request"

    /// Notification sent to the active split view to resize the split.
    static let didResizeSplit = Notification.Name("com.mitchellh.void.didResizeSplit")
    static let ResizeSplitDirectionKey = didResizeSplit.rawValue + ".direction"
    static let ResizeSplitAmountKey = didResizeSplit.rawValue + ".amount"

    /// Notification sent to the split root to equalize split sizes
    static let didEqualizeSplits = Notification.Name("com.mitchellh.void.didEqualizeSplits")

    /// Notification that renderer health changed
    static let didUpdateRendererHealth = Notification.Name("com.mitchellh.void.didUpdateRendererHealth")

    /// Notifications related to key sequences
    static let didContinueKeySequence = Notification.Name("com.mitchellh.void.didContinueKeySequence")
    static let didEndKeySequence = Notification.Name("com.mitchellh.void.didEndKeySequence")
    static let KeySequenceKey = didContinueKeySequence.rawValue + ".key"

    /// Notifications related to key tables
    static let didChangeKeyTable = Notification.Name("com.mitchellh.void.didChangeKeyTable")
    static let KeyTableKey = didChangeKeyTable.rawValue + ".action"
}

// Make the input enum hashable.
extension void_input_key_e: @retroactive Hashable {}
