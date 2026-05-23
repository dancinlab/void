import SwiftUI
import VoidKit

extension VD {
    /// Maps to a `void_config_t` and the various operations on that.
    class Config: ObservableObject {
        // The underlying C pointer to the Void config structure. This
        // should never be accessed directly. Any operations on this should
        // be called from the functions on this or another class.
        private(set) var config: void_config_t? {
            didSet {
                // Free the old value whenever we change
                guard let old = oldValue else { return }
                void_config_free(old)
            }
        }

        /// True if the configuration is loaded
        var loaded: Bool { config != nil }

        /// Return the errors found while loading the configuration.
        var errors: [String] {
            guard let cfg = self.config else { return [] }

            var diags: [String] = []
            let diagsCount = void_config_diagnostics_count(cfg)
            for i in 0..<diagsCount {
                let diag = void_config_get_diagnostic(cfg, UInt32(i))
                let message = String(cString: diag.message)
                diags.append(message)
            }

            return diags
        }

        init(config: void_config_t?) {
            self.config = config
        }

        convenience init(at path: String? = nil, finalize: Bool = true) {
            self.init(config: Self.loadConfig(at: path, finalize: finalize))
        }

        convenience init(clone config: void_config_t) {
            self.init(config: void_config_clone(config))
        }

        func clone(config: void_config_t) {
            self.config = config
        }

        deinit {
            self.config = nil
        }

        /// Initializes a new configuration and loads all the values.
        /// - Parameters:
        ///   - path: An optional preferred config file path. Pass `nil` to load the default configuration files.
        ///   - finalize: Whether to finalize the configuration to populate default values.
        static func loadConfig(at path: String?, finalize: Bool) -> void_config_t? {
            // Initialize the global configuration.
            guard let cfg = void_config_new() else {
                logger.critical("void_config_new failed")
                return nil
            }

            // Load our configuration from files, CLI args, and then any referenced files.
            // We only do this on macOS because other Apple platforms do not have the
            // same filesystem concept.
#if os(macOS)
            if let path {
                void_config_load_file(cfg, path)
            } else {
                void_config_load_default_files(cfg)
            }

            // We only load CLI args when not running in Xcode because in Xcode we
            // pass some special parameters to control the debugger.
            if !isRunningInXcode() {
                void_config_load_cli_args(cfg)
            }

            void_config_load_recursive_files(cfg)
#endif

            // TODO: we'd probably do some config loading here... for now we'd
            // have to do this synchronously. When we support config updating we can do
            // this async and update later.

            if finalize {
                // Finalize will make our defaults available.
                void_config_finalize(cfg)
            }
            // Log any configuration errors. These will be automatically shown in a
            // pop-up window too.
            let diagsCount = void_config_diagnostics_count(cfg)
            if diagsCount > 0 {
                logger.warning("config error: \(diagsCount) configuration errors on reload")
                var diags: [String] = []
                for i in 0..<diagsCount {
                    let diag = void_config_get_diagnostic(cfg, UInt32(i))
                    let message = String(cString: diag.message)
                    diags.append(message)
                    logger.warning("config error: \(message)")
                }
            }

            return cfg
        }

#if os(macOS)
        // MARK: - Keybindings

        /// Return the key equivalent for the given action. The action is the name of the action
        /// in the Void configuration. For example `keybind = cmd+q=quit` in Void
        /// configuration would be "quit" action.
        ///
        /// Returns nil if there is no key equivalent for the given action.
        func keyboardShortcut(for action: String) -> KeyboardShortcut? {
            guard let cfg = self.config else { return nil }

            let trigger = void_config_trigger(cfg, action, UInt(action.lengthOfBytes(using: .utf8)))
            return VD.keyboardShortcut(for: trigger)
        }
#endif

        // MARK: - Configuration Values

        /// For all of the configuration values below, see the associated Void documentation for
        /// details on what each means. We only add documentation if there is a strange conversion
        /// due to the embedded library and Swift.

        var bellFeatures: BellFeatures {
            guard let config = self.config else { return .init() }
            var v: CUnsignedInt = 0
            let key = "bell-features"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return .init() }
            return .init(rawValue: v)
        }

        var bellAudioPath: ConfigPath? {
            guard let config = self.config else { return nil }
            var v = void_config_path_s()
            let key = "bell-audio-path"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            let path = String(cString: v.path)
            return path.isEmpty ? nil : ConfigPath(path: path, optional: v.optional)
        }

        var bellAudioVolume: Float {
            guard let config = self.config else { return 0.5 }
            var v: Double = 0.5
            let key = "bell-audio-volume"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return Float(v)
        }

        var notifyOnCommandFinish: NotifyOnCommandFinish {
            guard let config = self.config else { return .never }
            var v: UnsafePointer<Int8>?
            let key = "notify-on-command-finish"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return .never }
            guard let ptr = v else { return .never }
            return NotifyOnCommandFinish(rawValue: String(cString: ptr)) ?? .never
        }

        var notifyOnCommandFinishAction: NotifyOnCommandFinishAction {
            let defaultValue = NotifyOnCommandFinishAction.bell
            guard let config = self.config else { return defaultValue }
            var v: CUnsignedInt = 0
            let key = "notify-on-command-finish-action"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            return .init(rawValue: v)
        }

        var notifyOnCommandFinishAfter: Duration {
            guard let config = self.config else { return .seconds(5) }
            var v: UInt = 0
            let key = "notify-on-command-finish-after"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return .milliseconds(v)
        }

        var splitPreserveZoom: SplitPreserveZoom {
            guard let config = self.config else { return .init() }
            var v: CUnsignedInt = 0
            let key = "split-preserve-zoom"
            guard void_config_get(config, &v, key, UInt(key.count)) else { return .init() }
            return .init(rawValue: v)
        }

        var initialWindow: Bool {
            guard let config = self.config else { return true }
            var v = true
            let key = "initial-window"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var macosTabKeyCycles: Bool {
            // Runtime override from the Shell menu wins over the config file.
            // Why: the menu toggle has to take effect immediately without
            //   requiring a config reload or app restart.
            if let override = UserDefaults.void.object(forKey: Self.tabKeyCyclesOverrideKey) as? Bool {
                return override
            }
            guard let config = self.config else { return false }
            var v = false
            let key = "macos-tab-key-cycles"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        /// UserDefaults key for the Shell menu's runtime override of
        /// `macos-tab-key-cycles`. Persisted so the user's choice survives
        /// restarts even when the config file isn't edited.
        static let tabKeyCyclesOverrideKey = "VoidMacosTabKeyCyclesOverride"

        var shouldQuitAfterLastWindowClosed: Bool {
            guard let config = self.config else { return true }
            var v = false
            let key = "quit-after-last-window-closed"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var title: String? {
            guard let config = self.config else { return nil }
            var v: UnsafePointer<Int8>?
            let key = "title"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            guard let ptr = v else { return nil }
            return String(cString: ptr)
        }

        var windowSaveState: String {
            guard let config = self.config else { return "" }
            var v: UnsafePointer<Int8>?
            let key = "window-save-state"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return "" }
            guard let ptr = v else { return "" }
            return String(cString: ptr)
        }

        /// Threshold (in consecutive launches) for auto-GC of stale orphan
        /// ring files under `~/.void/sessions/by-uuid/`. Zero disables.
        /// See `SessionManifest.runAutoGC` for the bookkeeping. Default 3
        /// is enforced in Zig (`@"session-orphan-gc-threshold": u8 = 3`),
        /// but we re-apply it here so a missing libvoid_config is still
        /// safe.
        var sessionOrphanGCThreshold: Int {
            let defaultValue: Int = 3
            guard let config = self.config else { return defaultValue }
            var v: UInt8 = 0
            let key = "session-orphan-gc-threshold"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            return Int(v)
        }

        var windowPositionX: Int16? {
            guard let config = self.config else { return nil }
            var v: Int16 = 0
            let key = "window-position-x"
            return void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) ? v : nil
        }

        var windowPositionY: Int16? {
            guard let config = self.config else { return nil }
            var v: Int16 = 0
            let key = "window-position-y"
            return void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) ? v : nil
        }

        var windowNewTabPosition: String {
            guard let config = self.config else { return "" }
            var v: UnsafePointer<Int8>?
            let key = "window-new-tab-position"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return "" }
            guard let ptr = v else { return "" }
            return String(cString: ptr)
        }

        var windowDecorations: Bool {
            let defaultValue = true
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "window-decoration"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return WindowDecoration(rawValue: str)?.enabled() ?? defaultValue
        }

        var windowTheme: String? {
            guard let config = self.config else { return nil }
            var v: UnsafePointer<Int8>?
            let key = "window-theme"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            guard let ptr = v else { return nil }
            return String(cString: ptr)
        }

        var windowStepResize: Bool {
            guard let config = self.config else { return true }
            var v = false
            let key = "window-step-resize"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        /// Whether dragging a split divider (direct mouse drag on the line, or
        /// the magnetic Cmd+drag gesture) changes pane proportions. Default
        /// false — visual hints still render and double-tap-to-equalize still
        /// works, but no resize is committed unless the user opts in via
        /// `split-divider-resize`.
        var splitDividerResize: Bool {
            guard let config = self.config else { return false }
            var v = false
            let key = "split-divider-resize"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        /// Returns the fullscreen mode if fullscreen is enabled, or nil if disabled.
        /// This parses the `fullscreen` enum config which supports both
        /// native and non-native fullscreen modes.
        #if canImport(AppKit)
        var windowFullscreen: FullscreenMode? {
            guard let config = self.config else { return nil }
            var v: UnsafePointer<Int8>?
            let key = "fullscreen"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            guard let ptr = v else { return nil }
            let str = String(cString: ptr)
            return switch str {
            case "false":
                nil
            case "true":
                .native
            case "non-native":
                .nonNative
            case "non-native-visible-menu":
                .nonNativeVisibleMenu
            case "non-native-padded-notch":
                .nonNativePaddedNotch
            default:
                nil
            }
        }
        #else
        var windowFullscreen: Bool {
            guard let config = self.config else { return false }
            var v: UnsafePointer<Int8>?
            let key = "fullscreen"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return false }
            guard let ptr = v else { return false }
            let str = String(cString: ptr)
            return str != "false"
        }
        #endif

        /// Returns the fullscreen mode for toggle actions (keybindings).
        /// This is controlled by `macos-non-native-fullscreen` config.
        #if canImport(AppKit)
        var windowFullscreenMode: FullscreenMode {
            let defaultValue: FullscreenMode = .native
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-non-native-fullscreen"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return switch str {
            case "false":
                    .native
            case "true":
                    .nonNative
            case "visible-menu":
                    .nonNativeVisibleMenu
            case "padded-notch":
                    .nonNativePaddedNotch
            default:
                defaultValue
            }
        }
        #endif

        var windowTitleFontFamily: String? {
            guard let config = self.config else { return nil }
            var v: UnsafePointer<Int8>?
            let key = "window-title-font-family"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            guard let ptr = v else { return nil }
            return String(cString: ptr)
        }

        var macosWindowButtons: MacOSWindowButtons {
            let defaultValue = MacOSWindowButtons.visible
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-window-buttons"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return MacOSWindowButtons(rawValue: str) ?? defaultValue
        }

        var macosTitlebarStyle: MacOSTitlebarStyle {
            let defaultValue = MacOSTitlebarStyle.transparent
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-titlebar-style"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            return MacOSTitlebarStyle(rawValue: String(cString: ptr)) ?? defaultValue
        }

        var macosTitlebarProxyIcon: MacOSTitlebarProxyIcon {
            let defaultValue = MacOSTitlebarProxyIcon.visible
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-titlebar-proxy-icon"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return MacOSTitlebarProxyIcon(rawValue: str) ?? defaultValue
        }

        var macosDockDropBehavior: MacDockDropBehavior {
            let defaultValue = MacDockDropBehavior.new_tab
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-dock-drop-behavior"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return MacDockDropBehavior(rawValue: str) ?? defaultValue
        }

        var macosWindowShadow: Bool {
            guard let config = self.config else { return false }
            var v = false
            let key = "macos-window-shadow"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var macosIcon: MacOSIcon {
            let defaultValue = MacOSIcon.official
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-icon"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return MacOSIcon(rawValue: str) ?? defaultValue
        }

        var macosCustomIcon: String {
            #if os(macOS)
            let defaultValue = NSString("~/.config/void/VD.icns").expandingTildeInPath
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-custom-icon"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            guard let path = NSString(utf8String: ptr) else { return defaultValue }
            return path.expandingTildeInPath
            #else
            return ""
            #endif
        }

        var macosIconFrame: MacOSIconFrame {
            let defaultValue = MacOSIconFrame.aluminum
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-icon-frame"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return MacOSIconFrame(rawValue: str) ?? defaultValue
        }

        var macosIconGhostColor: OSColor? {
            guard let config = self.config else { return nil }
            var v: void_config_color_s = .init()
            let key = "macos-icon-ghost-color"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            return .init(void: v)
        }

        var macosIconScreenColor: [OSColor]? {
            guard let config = self.config else { return nil }
            var v: void_config_color_list_s = .init()
            let key = "macos-icon-screen-color"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            guard v.len > 0 else { return nil }
            let buffer = UnsafeBufferPointer(start: v.colors, count: v.len)
            return buffer.map { .init(void: $0) }
        }

        var macosHidden: MacHidden {
            guard let config = self.config else { return .never }
            var v: UnsafePointer<Int8>?
            let key = "macos-hidden"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return .never }
            guard let ptr = v else { return .never }
            let str = String(cString: ptr)
            return MacHidden(rawValue: str) ?? .never
        }

        var focusFollowsMouse: Bool {
            guard let config = self.config else { return false }
            var v = false
            let key = "focus-follows-mouse"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var backgroundColor: Color {
            var color: void_config_color_s = .init()
            let bg_key = "background"
            if !void_config_get(config, &color, bg_key, UInt(bg_key.lengthOfBytes(using: .utf8))) {
#if os(macOS)
                return Color(NSColor.windowBackgroundColor)
#elseif os(iOS)
                return Color(UIColor.systemBackground)
#else
#error("unsupported")
#endif
            }

            return .init(
                red: Double(color.r) / 255,
                green: Double(color.g) / 255,
                blue: Double(color.b) / 255
            )
        }

        var backgroundOpacity: Double {
            guard let config = self.config else { return 1 }
            var v: Double = 1
            let key = "background-opacity"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var backgroundBlur: BackgroundBlur {
            guard let config = self.config else { return .disabled }
            var v: Int16 = 0
            let key = "background-blur"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return BackgroundBlur(fromCValue: v)
        }

        var unfocusedSplitOpacity: Double {
            guard let config = self.config else { return 1 }
            var opacity: Double = 0.85
            let key = "unfocused-split-opacity"
            _ = void_config_get(config, &opacity, key, UInt(key.lengthOfBytes(using: .utf8)))
            return 1 - opacity
        }

        var gridDimInactive: Bool {
            // Runtime override from the Grid menu wins over the config file,
            // for the same reason as macosTabKeyCycles.
            if let override = UserDefaults.void.object(forKey: Self.gridDimInactiveOverrideKey) as? Bool {
                return override
            }
            guard let config = self.config else { return false }
            var v = false
            let key = "grid-dim-inactive"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        /// UserDefaults key for the Grid menu's runtime override of
        /// `grid-dim-inactive`.
        static let gridDimInactiveOverrideKey = "VoidGridDimInactiveOverride"

        /// UserDefaults key for the last-picked grid/tab layout (cmd+G).
        /// Values: "grid" or "tab". When set to "grid", `cmd+T` from a
        /// single-tab window adds a grid cell instead of opening a new tab,
        /// so a fresh launch picks up where the user left off.
        static let gridModePreferenceKey = "VoidGridModePreference"

        var unfocusedSplitFill: Color {
            guard let config = self.config else { return .white }

            var color: void_config_color_s = .init()
            let key = "unfocused-split-fill"
            if !void_config_get(config, &color, key, UInt(key.lengthOfBytes(using: .utf8))) {
                let bg_key = "background"
                _ = void_config_get(config, &color, bg_key, UInt(bg_key.lengthOfBytes(using: .utf8)))
            }

            return .init(
                red: Double(color.r) / 255,
                green: Double(color.g) / 255,
                blue: Double(color.b) / 255
            )
        }

        var splitDividerColor: Color {
            let backgroundColor = OSColor(backgroundColor)
            let isLightBackground = backgroundColor.isLightColor
            let newColor = isLightBackground ? backgroundColor.darken(by: 0.08) : backgroundColor.darken(by: 0.4)

            guard let config = self.config else { return Color(newColor) }

            var color: void_config_color_s = .init()
            let key = "split-divider-color"
            if !void_config_get(config, &color, key, UInt(key.lengthOfBytes(using: .utf8))) {
                return Color(newColor)
            }

            return .init(
                red: Double(color.r) / 255,
                green: Double(color.g) / 255,
                blue: Double(color.b) / 255
            )
        }

        #if canImport(AppKit)
        var quickTerminalPosition: QuickTerminalPosition {
            guard let config = self.config else { return .top }
            var v: UnsafePointer<Int8>?
            let key = "quick-terminal-position"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return .top }
            guard let ptr = v else { return .top }
            let str = String(cString: ptr)
            return QuickTerminalPosition(rawValue: str) ?? .top
        }

        var quickTerminalScreen: QuickTerminalScreen {
            guard let config = self.config else { return .main }
            var v: UnsafePointer<Int8>?
            let key = "quick-terminal-screen"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return .main }
            guard let ptr = v else { return .main }
            let str = String(cString: ptr)
            return QuickTerminalScreen(fromVoidConfig: str) ?? .main
        }

        var quickTerminalAnimationDuration: Double {
            guard let config = self.config else { return 0.2 }
            var v: Double = 0.2
            let key = "quick-terminal-animation-duration"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var quickTerminalAutoHide: Bool {
            guard let config = self.config else { return true }
            var v = true
            let key = "quick-terminal-autohide"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var quickTerminalSpaceBehavior: QuickTerminalSpaceBehavior {
            guard let config = self.config else { return .move }
            var v: UnsafePointer<Int8>?
            let key = "quick-terminal-space-behavior"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return .move }
            guard let ptr = v else { return .move }
            let str = String(cString: ptr)
            return QuickTerminalSpaceBehavior(fromVoidConfig: str) ?? .move
        }

        var quickTerminalSize: QuickTerminalSize {
            guard let config = self.config else { return QuickTerminalSize() }
            var v = void_config_quick_terminal_size_s()
            let key = "quick-terminal-size"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return QuickTerminalSize() }
            return QuickTerminalSize(from: v)
        }
        #endif

        var resizeOverlay: ResizeOverlay {
            guard let config = self.config else { return .after_first }
            var v: UnsafePointer<Int8>?
            let key = "resize-overlay"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return .after_first }
            guard let ptr = v else { return .after_first }
            let str = String(cString: ptr)
            return ResizeOverlay(rawValue: str) ?? .after_first
        }

        var resizeOverlayPosition: ResizeOverlayPosition {
            let defaultValue = ResizeOverlayPosition.center
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "resize-overlay-position"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return ResizeOverlayPosition(rawValue: str) ?? defaultValue
        }

        var resizeOverlayDuration: UInt {
            guard let config = self.config else { return 1000 }
            var v: UInt = 0
            let key = "resize-overlay-duration"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var undoTimeout: Duration {
            guard let config = self.config else { return .seconds(5) }
            var v: UInt = 0
            let key = "undo-timeout"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return .milliseconds(v)
        }

        var autoUpdate: AutoUpdate? {
            guard let config = self.config else { return nil }
            var v: UnsafePointer<Int8>?
            let key = "auto-update"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            guard let ptr = v else { return nil }
            let str = String(cString: ptr)
            return AutoUpdate(rawValue: str)
        }

        var autoUpdateChannel: AutoUpdateChannel {
            let defaultValue = AutoUpdateChannel.stable
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "auto-update-channel"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return AutoUpdateChannel(rawValue: str) ?? defaultValue
        }

        var autoSecureInput: Bool {
            guard let config = self.config else { return true }
            var v = false
            let key = "macos-auto-secure-input"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var secureInputIndication: Bool {
            guard let config = self.config else { return true }
            var v = false
            let key = "macos-secure-input-indication"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var macosAppleScript: Bool {
            guard let config = self.config else { return true }
            var v = false
            let key = "macos-applescript"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var maximize: Bool {
            guard let config = self.config else { return true }
            var v = false
            let key = "maximize"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }

        var macosShortcuts: MacShortcuts {
            let defaultValue = MacShortcuts.ask
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "macos-shortcuts"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return MacShortcuts(rawValue: str) ?? defaultValue
        }

        var scrollbar: Scrollbar {
            let defaultValue = Scrollbar.system
            guard let config = self.config else { return defaultValue }
            var v: UnsafePointer<Int8>?
            let key = "scrollbar"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return defaultValue }
            guard let ptr = v else { return defaultValue }
            let str = String(cString: ptr)
            return Scrollbar(rawValue: str) ?? defaultValue
        }

        var commandPaletteEntries: [VD.Command] {
            guard let config = self.config else { return [] }
            var v: void_config_command_list_s = .init()
            let key = "command-palette-entry"
            guard void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return [] }
            guard v.len > 0 else { return [] }
            let buffer = UnsafeBufferPointer(start: v.commands, count: v.len)
            return buffer.map { VD.Command(cValue: $0) }
        }

        var progressStyle: Bool {
            guard let config = self.config else { return true }
            var v = true
            let key = "progress-style"
            _ = void_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))
            return v
        }
    }
}

// MARK: Configuration Enums

extension VD.Config {
    enum AutoUpdate: String {
        case off
        case check
        case download
    }

    /// Background blur configuration that maps from the C API values.
    /// Positive values represent blur radius, special negative values
    /// represent macOS-specific glass effects.
    enum BackgroundBlur: Equatable {
        case disabled
        case radius(Int)
        case macosGlassRegular
        case macosGlassClear

        init(fromCValue value: Int16) {
            switch value {
            case 0:
                self = .disabled
            case -1:
                if #available(macOS 26.0, *) {
                    self = .macosGlassRegular
                } else {
                    self = .disabled
                }
            case -2:
                if #available(macOS 26.0, *) {
                    self = .macosGlassClear
                } else {
                    self = .disabled
                }
            default:
                self = .radius(Int(value))
            }
        }

        var isEnabled: Bool {
            switch self {
            case .disabled:
                return false
            default:
                return true
            }
        }

        /// Returns true if this is a macOS glass style (regular or clear).
        var isGlassStyle: Bool {
            switch self {
            case .macosGlassRegular, .macosGlassClear:
                return true
            default:
                return false
            }
        }

        /// Returns the blur radius if applicable, nil for glass effects.
        var radius: Int? {
            switch self {
            case .disabled:
                return nil
            case .radius(let r):
                return r
            case .macosGlassRegular, .macosGlassClear:
                return nil
            }
        }
    }

    struct BellFeatures: OptionSet {
        let rawValue: CUnsignedInt

        static let system = BellFeatures(rawValue: 1 << 0)
        static let audio = BellFeatures(rawValue: 1 << 1)
        static let attention = BellFeatures(rawValue: 1 << 2)
        static let title = BellFeatures(rawValue: 1 << 3)
        static let border = BellFeatures(rawValue: 1 << 4)
    }

    struct SplitPreserveZoom: OptionSet {
        let rawValue: CUnsignedInt

        static let navigation = SplitPreserveZoom(rawValue: 1 << 0)
    }

    enum MacDockDropBehavior: String {
        case new_tab = "new-tab"
        case new_window = "new-window"
    }

    enum MacHidden: String {
        case never
        case always
    }

    enum MacShortcuts: String {
        case allow
        case deny
        case ask
    }

    enum Scrollbar: String {
        case system
        case never
    }

    enum ResizeOverlay: String {
        case always
        case never
        case after_first = "after-first"
    }

    enum ResizeOverlayPosition: String {
        case center
        case top_left = "top-left"
        case top_center = "top-center"
        case top_right = "top-right"
        case bottom_left = "bottom-left"
        case bottom_center = "bottom-center"
        case bottom_right = "bottom-right"

        func top() -> Bool {
            switch self {
            case .top_left, .top_center, .top_right: return true
            default: return false
            }
        }

        func bottom() -> Bool {
            switch self {
            case .bottom_left, .bottom_center, .bottom_right: return true
            default: return false
            }
        }

        func left() -> Bool {
            switch self {
            case .top_left, .bottom_left: return true
            default: return false
            }
        }

        func right() -> Bool {
            switch self {
            case .top_right, .bottom_right: return true
            default: return false
            }
        }
    }

    enum WindowDecoration: String {
        case none
        case client
        case server
        case auto

        func enabled() -> Bool {
            switch self {
            case .client, .server, .auto: return true
            case .none: return false
            }
        }
    }

    enum NotifyOnCommandFinish: String {
        case never
        case unfocused
        case always
    }

    struct NotifyOnCommandFinishAction: OptionSet {
        let rawValue: CUnsignedInt

        static let bell = NotifyOnCommandFinishAction(rawValue: 1 << 0)
        static let notify = NotifyOnCommandFinishAction(rawValue: 1 << 1)
    }

    enum MacOSTitlebarStyle: String {
        static let `default` = MacOSTitlebarStyle.transparent
        case native, transparent, tabs, hidden
    }
}

/// Whether Ctrl+Backspace and Ctrl+Delete are forwarded to the shell with the
/// Control modifier intact (readline default in bash/zsh erases the entire input
/// line, which is what users hit when they reported "entire text gets deleted"),
/// or stripped of Control so the shell sees a plain Backspace/Delete (one-char
/// erase).
///
/// Read once from `$XDG_CONFIG_HOME/void/config.void` (or `~/.config/void/config.void`)
/// at first access and cached.
///
/// config.void key:
///     ctrl-erase-line = true | false
/// Default: false (Ctrl is stripped → behaves like plain Backspace/Delete).
enum VoidCtrlEraseLine {
    static let enabled: Bool = VoidConfigBool.read(key: "ctrl-erase-line", default: false)
}

/// Whether Alt+Backspace and Alt+Delete are forwarded to the shell with the
/// Option modifier intact (readline kills a word backward / forward — the
/// common "delete word" shortcut), or stripped of Option so the shell sees a
/// plain Backspace/Delete.
///
/// config.void key:
///     alt-erase-word = true | false
/// Default: true (kill-word behavior preserved).
enum VoidAltEraseWord {
    static let enabled: Bool = VoidConfigBool.read(key: "alt-erase-word", default: true)
}

/// Shared lightweight reader for boolean keys that only the Swift app cares
/// about (VoidKit/Zig parser does not need to know them). Reads once at first
/// access. Lines starting with `#` and blank lines are ignored.
private enum VoidConfigBool {
    static func read(key: String, default fallback: Bool) -> Bool {
        let env = ProcessInfo.processInfo.environment
        let baseDir: URL = {
            if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
                return URL(fileURLWithPath: xdg)
            }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }()
        let url = baseDir.appendingPathComponent("void/config.void")
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return fallback }
        for raw in data.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard line.hasPrefix(key) else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == key else { continue }
            return parts[1].lowercased() == "true"
        }
        return fallback
    }
}

/// How a pwd-like path is rendered in tab/window titles and grid pane labels.
/// Read once from `$XDG_CONFIG_HOME/void/config.void` (or `~/.config/void/config.void`)
/// at first access and cached — no per-frame disk hits.
///
/// config.void key:
///     path-title-style = basename | full | hidden
/// Default: basename. Examples for `~/core/void`:
///   basename → "void"
///   full     → "~/core/void"
///   hidden   → ""
enum VoidPathTitleStyle: String {
    case basename
    case full
    case hidden

    static let current: VoidPathTitleStyle = readFromConfig()

    /// Apply the style to an absolute path string. Empty/non-path inputs pass through.
    static func format(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        switch current {
        case .basename: return (path as NSString).lastPathComponent
        case .full:     return (path as NSString).abbreviatingWithTildeInPath
        case .hidden:   return ""
        }
    }

    /// True if the given title looks like a single bare path (no spaces, starts
    /// with `/` or `~/`). Used to decide whether to apply the style to a tab title.
    static func isPathLike(_ s: String) -> Bool {
        guard !s.isEmpty, !s.contains(" ") else { return false }
        return s.hasPrefix("/") || s.hasPrefix("~/")
    }

    private static func readFromConfig() -> VoidPathTitleStyle {
        let env = ProcessInfo.processInfo.environment
        let baseDir: URL = {
            if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
                return URL(fileURLWithPath: xdg)
            }
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }()
        let url = baseDir.appendingPathComponent("void/config.void")
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return .basename }
        for raw in data.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard line.hasPrefix("path-title-style") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            return VoidPathTitleStyle(rawValue: parts[1]) ?? .basename
        }
        return .basename
    }
}
