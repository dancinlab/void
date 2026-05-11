import AppKit

extension Notification.Name {
    /// Distributed Notification for DockTilePlugin to update icon
    ///
    /// Void -> DockTilePlugin
    static let voidIconDidChange = Notification.Name("com.dancinlab.void.iconDidChange")
}
