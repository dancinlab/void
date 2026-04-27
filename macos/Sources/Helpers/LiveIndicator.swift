import AppKit
import SwiftUI

/// Visual constants for the "live" indicator (the small filled circle that
/// flags an unfocused pane/tab whose surface bell rang). Single source of
/// truth so the SwiftUI grid badge and the AppKit tab/title image stay in
/// lockstep — change a value here, both surfaces update.
enum LiveIndicator {
    /// Diameter in points. Same value used for the SwiftUI Circle frame
    /// and the NSImage attachment in tab/window titles.
    static let size: CGFloat = 8

    /// Brand "live" green: R 108 / G 184 / B 110 (#6CB86E).
    static let red: CGFloat = 108.0 / 255.0
    static let green: CGFloat = 184.0 / 255.0
    static let blue: CGFloat = 110.0 / 255.0

    static var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    static var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1)
    }

    /// Sentinel prefix appended to `window.title` (and matched on by
    /// `TerminalWindow.attributedTitle`) when the live indicator should
    /// render. Kept as a real character so consumers reading raw
    /// `window.title` still see something legible.
    static let titlePrefix = "● "
}
