import Foundation

extension Void {
    /// This is a delegate that should be applied to your global app delegate for VoidKit
    /// to perform app-global operations.
    protocol Delegate {
        /// Look up a surface within the application by ID.
        func voidSurface(id: UUID) -> SurfaceView?
    }
}
