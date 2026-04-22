import VoidKit

extension FullscreenMode {
    /// Initialize from a Void fullscreen action.
    static func from(void: void_action_fullscreen_e) -> Self? {
        return switch void {
        case VOID_FULLSCREEN_NATIVE:
                .native

        case VOID_FULLSCREEN_MACOS_NON_NATIVE:
                .nonNative

        case VOID_FULLSCREEN_MACOS_NON_NATIVE_VISIBLE_MENU:
                .nonNativeVisibleMenu

        case VOID_FULLSCREEN_MACOS_NON_NATIVE_PADDED_NOTCH:
                .nonNativePaddedNotch

        default:
            nil
        }
    }
}
