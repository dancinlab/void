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
        // sRGB explicitly — `NSColor(red:…)` uses calibrated/device RGB,
        // which gets gamma-shifted on Retina displays and renders as a
        // noticeably lighter mint instead of the intended #6CB86E.
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// Sentinel prefix appended to `window.title` (and matched on by
    /// `TerminalWindow.attributedTitle`) when the live indicator should
    /// render. Kept as a real character so consumers reading raw
    /// `window.title` still see something legible.
    static let titlePrefix = "● "
}

/// A small filled-circle NSView used as the macOS tab-strip live
/// indicator overlay. Lives as a sibling subview of `NSTabBar` (not a
/// child of `NSTabButton`) so it escapes the per-button alpha that
/// inactive tabs get — the whole reason this view exists is that an
/// inline colored bullet in attributedTitle dims along with the rest
/// of an inactive tab's text. Identifiable via class type so the host
/// can find/replace existing dots cheaply on each title change.
final class LiveDotView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = LiveIndicator.nsColor.cgColor
        layer?.cornerRadius = frame.width / 2
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    // Hit-testing returns nil so a click on the dot still selects the
    // underlying tab button instead of being eaten by the overlay.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
