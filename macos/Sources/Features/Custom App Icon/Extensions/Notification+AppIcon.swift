import AppKit

extension Notification.Name {
    /// Distributed Notification for DockTilePlugin to update icon
    ///
    /// Void -> DockTilePlugin
    static let voidIconDidChange = Notification.Name("com.need-singularity.void.iconDidChange")
}
