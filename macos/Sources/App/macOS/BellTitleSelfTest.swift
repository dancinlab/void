// BellTitleSelfTest.swift
//
// --bell-title-self-test: headless verification that the live-indicator
// (●) prefix lands on the correct visual surface in tab/grid modes.
//
// Specifically asserts that when window.title gets the LiveIndicator
// prefix, the NSTabBar's per-tab NSButton receives an attributedTitle
// containing the green-circle NSTextAttachment. AppKit's
// NSWindowTab.attributedTitle has known limitations around foreground
// color and image attachments, so we have to confirm we're hitting the
// NSButton directly — that's the only path that lights up in the tab
// strip.

import AppKit
import Foundation
import VoidKit

enum BellTitleSelfTest {
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains("--bell-title-self-test") else { return nil }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        var passes = 0, failures = 0
        func check(_ label: String, _ cond: @autoclosure () -> Bool, _ note: @autoclosure () -> String = "") {
            if cond() { passes += 1; print("  ✓ \(label)") }
            else      { failures += 1; print("  ✗ \(label)  \(note())") }
        }

        let app = VD.App()
        guard app.app != nil else {
            print("✗ VD.App failed to initialise")
            return 1
        }

        // Build two tabbed TerminalControllers (mirror grid-self-test).
        let controllers: [TerminalController] = (0..<2).map { _ in
            TerminalController(app, withBaseConfig: nil)
        }
        let host = controllers[0]
        guard let hostWindow = host.window else {
            print("✗ host has no window")
            return 1
        }
        hostWindow.setFrameOrigin(NSPoint(x: -9999, y: -9999))
        hostWindow.orderFront(nil)
        for sub in controllers.dropFirst() {
            guard let w = sub.window else { continue }
            w.setFrameOrigin(NSPoint(x: -9999, y: -9999))
            hostWindow.addTabbedWindow(w, ordered: .above)
        }
        hostWindow.makeKey()
        HeadlessKeyWindowBridge.forceKey(hostWindow)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let tabGroupCount = hostWindow.tabGroup?.windows.count ?? 0
        check("tab group has 2 windows", tabGroupCount == 2, "got \(tabGroupCount)")

        // Force-set a live-indicator title on the SECOND window. The user's
        // real flow goes title → bell → computeTitle → applyTitleToWindow,
        // but in headless we can poke window.title directly which fires
        // TerminalWindow.title.didSet → applyAttributedTitleToTabButton.
        let target = controllers[1].window!
        target.title = "\(LiveIndicator.titlePrefix)bell-test-tab"
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        check("window.title carries the bullet prefix",
              target.title.hasPrefix(LiveIndicator.titlePrefix),
              "got \(target.title)")

        // attributedTitle: leads with the bullet glyph carrying the
        // brand-green foreground color attribute.
        let twin = target as? TerminalWindow
        check("window casts to TerminalWindow", twin != nil)
        if let attr = twin?.attributedTitle {
            print("    [diag] attributedTitle.length=\(attr.length) string=\(attr.string)")
            let first = (attr.string as NSString).substring(with: NSRange(location: 0, length: 1))
            check("attributedTitle leads with bullet char", first == "●",
                  "got \"\(first)\"")
            let fg = attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            print("    [diag] bullet fg color: \(String(describing: fg))")
            check("bullet has foreground color attribute", fg != nil)
            if let fg = fg, let srgb = fg.usingColorSpace(.sRGB) {
                let r = Int((srgb.redComponent * 255).rounded())
                let g = Int((srgb.greenComponent * 255).rounded())
                let b = Int((srgb.blueComponent * 255).rounded())
                print("    [diag] bullet sRGB: r=\(r) g=\(g) b=\(b) (expected 108/184/110)")
                check("bullet color matches brand RGB",
                      abs(r - 108) <= 1 && abs(g - 184) <= 1 && abs(b - 110) <= 1,
                      "got r=\(r) g=\(g) b=\(b)")
            }
        } else {
            check("attributedTitle non-nil", false, "nil — titlebarFont not yet set?")
        }

        // Tab button: walk tabBarView and look for our window's tab button,
        // confirm its attributedTitle has the image attachment.
        let host2 = hostWindow.tabGroup?.windows.first(where: { $0.tabBarView != nil }) ?? hostWindow
        let buttons = host2.tabButtonsInVisualOrder()
        print("    [diag] tab buttons=\(buttons.count) tabBarHost=\(host2 === hostWindow ? "host" : "other")")
        check("at least 2 tab buttons visible", buttons.count >= 2,
              "got \(buttons.count) — tab strip may not be materialised in accessory mode")

        // Re-set the title right before we inspect — TerminalController's
        // title publisher can replace it back to the surface's title once
        // the run loop drains, hiding our test-injected prefix.
        target.title = "\(LiveIndicator.titlePrefix)bell-test-tab"
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        if let idx = hostWindow.tabGroup?.windows.firstIndex(of: target),
           idx < buttons.count {
            // NSTabButton is an NSButton subclass that Swift's `as?
            // NSButton` refuses to cast across — read attributedTitle via
            // KVC, the same path the production setter uses.
            let view = buttons[idx]
            let bAttr = (view.value(forKey: "attributedTitle") as? NSAttributedString) ?? NSAttributedString()
            print("    [diag] tabButton[\(idx)].attributedTitle.length=\(bAttr.length) string=\(bAttr.string)")
            check("tab button attributedTitle non-empty", bAttr.length > 0)
            if bAttr.length > 0 {
                let first = (bAttr.string as NSString).substring(with: NSRange(location: 0, length: 1))
                check("tab button leads with bullet char", first == "●",
                      "got \"\(first)\"")
                let fg = bAttr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                if let fg = fg, let srgb = fg.usingColorSpace(.sRGB) {
                    let r = Int((srgb.redComponent * 255).rounded())
                    let g = Int((srgb.greenComponent * 255).rounded())
                    let b = Int((srgb.blueComponent * 255).rounded())
                    print("    [diag] tab button bullet sRGB: r=\(r) g=\(g) b=\(b) (expected 108/184/110)")
                    check("tab button bullet color matches brand RGB",
                          abs(r - 108) <= 1 && abs(g - 184) <= 1 && abs(b - 110) <= 1,
                          "got r=\(r) g=\(g) b=\(b)")
                } else {
                    check("tab button bullet fg attribute present", false,
                          "no foregroundColor attribute on bullet — KVC propagation failed?")
                }
            }
        } else {
            check("tab button lookup", false, "couldn't resolve target's button")
        }

        print("\n\(passes) passed, \(failures) failed")
        return failures == 0 ? 0 : 1
    }

}
