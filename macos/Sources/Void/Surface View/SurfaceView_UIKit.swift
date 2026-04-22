import SwiftUI
import VoidKit

extension Void {
    /// The UIView implementation for a terminal surface.
    class SurfaceView: OSSurfaceView {
        // The current title of the surface as defined by the pty. This can be
        // changed with escape codes.
        @Published private(set) var title: String = "👻"

        /// True when the bell is active. This is set inactive on focus or event.
        @Published var bell: Bool = false

        private(set) var _surface: void_surface_t?

        override var surface: void_surface_t? {
            _surface
        }

        init(_ app: void_app_t, baseConfig: SurfaceConfiguration? = nil, uuid: UUID? = nil) {

            // Initialize with some default frame size. The important thing is that this
            // is non-zero so that our layer bounds are non-zero so that our renderer
            // can do SOMETHING.
            super.init(id: uuid, frame: CGRect(x: 0, y: 0, width: 800, height: 600))

            // Setup our surface. This will also initialize all the terminal IO.
            let surface_cfg = baseConfig ?? SurfaceConfiguration()
            let surface = surface_cfg.withCValue(view: self) { surface_cfg_c in
                void_surface_new(app, &surface_cfg_c)
            }
            guard let surface = surface else {
                // TODO
                return
            }
            self._surface = surface
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported for this view")
        }

        deinit {
            guard let surface = self.surface else { return }
            void_surface_free(surface)
        }

        override func focusDidChange(_ focused: Bool) {
            guard let surface = self.surface else { return }
            void_surface_set_focus(surface, focused)

            // On macOS 13+ we can store our continuous clock...
            if focused {
                focusInstant = ContinuousClock.now
            }
        }

        override func sizeDidChange(_ size: CGSize) {
            guard let surface = self.surface else { return }

            // Void wants to know the actual framebuffer size... It is very important
            // here that we use "size" and NOT the view frame. If we're in the middle of
            // an animation (i.e. a fullscreen animation), the frame will not yet be updated.
            // The size represents our final size we're going for.
            let scale = self.contentScaleFactor
            void_surface_set_content_scale(surface, scale, scale)
            void_surface_set_size(
                surface,
                UInt32(size.width * scale),
                UInt32(size.height * scale)
            )
        }

        // MARK: UIView

        override class var layerClass: AnyClass {
            return CAMetalLayer.self
        }

        override func didMoveToWindow() {
            sizeDidChange(frame.size)
        }
    }
}
