import AppKit

// MARK: Void Delegate

/// This implements the Void app delegate protocol which is used by the Void
/// APIs for app-global information.
extension AppDelegate: Void.Delegate {
    func voidSurface(id: UUID) -> Void.SurfaceView? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for surface in controller.surfaceTree where surface.id == id {
                return surface
            }
        }

        return nil
    }
}
