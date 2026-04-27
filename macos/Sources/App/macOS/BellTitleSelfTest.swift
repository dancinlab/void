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

        // attributedTitle: should be NSAttributedString starting with an
        // NSTextAttachment.
        let twin = target as? TerminalWindow
        check("window casts to TerminalWindow", twin != nil)
        if let attr = twin?.attributedTitle {
            print("    [diag] attributedTitle.length=\(attr.length) string=\(attr.string)")
            // First "character" of the attributed string should be the
            // NSAttachmentCharacter (U+FFFC) when an attachment leads.
            let first = (attr.string as NSString).substring(with: NSRange(location: 0, length: 1))
            check("attributedTitle leads with NSAttachmentCharacter",
                  first == "\u{FFFC}",
                  "got \"\(first)\"")
            // Verify .attachment attribute on range 0..1
            let attachment = attr.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
            check("attributedTitle range 0 has NSTextAttachment", attachment != nil)
            check("attachment image present", attachment?.image != nil)
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
                check("tab button leads with attachment char", first == "\u{FFFC}",
                      "got \"\(first)\" — title was set on the button but image attachment didn't propagate")
                let attachment = bAttr.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
                check("tab button has NSTextAttachment", attachment != nil)
                check("attachment image present", attachment?.image != nil)
            }
        } else {
            check("tab button lookup", false, "couldn't resolve target's button")
        }

        print("\n\(passes) passed, \(failures) failed")
        return failures == 0 ? 0 : 1
    }
}
