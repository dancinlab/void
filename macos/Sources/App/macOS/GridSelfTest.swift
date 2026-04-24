// GridSelfTest.swift
//
// --grid-self-test: reproduces the user's exact failure path inside the
// Void binary without any window server presence. Invoked BEFORE
// NSApplicationMain, sets .prohibited activation policy, builds real
// TerminalControllers with real VD.SurfaceViews, flattens into a grid,
// simulates cmd+N via voidFocusGridCell notification, and asserts on
// the post-state (first responder, surface.focused).
//
// Reproduces: "tab 여러개 띄움 → 그리드모드 → 터미널입력됨. 그리드를
// 다른걸로 포커싱이동 → 입력안됨"

import AppKit
import Foundation
import VoidKit

enum GridSelfTest {
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains("--grid-self-test") else { return nil }

        _ = NSApplication.shared
        // .accessory: no Dock icon, no menu bar, BUT windows can still
        // become key. .prohibited would block window.isKeyWindow from
        // ever being true, which breaks syncFocusToSurfaceTree's gating
        // and yields a false-positive focus bug report. Off-screen
        // positioning keeps the test invisible to the user.
        NSApp.setActivationPolicy(.accessory)

        var passes = 0, failures = 0
        func check(_ label: String, _ cond: @autoclosure () -> Bool, _ note: @autoclosure () -> String = "") {
            if cond() { passes += 1; print("  ✓ \(label)") }
            else      { failures += 1; print("  ✗ \(label)  \(note())") }
        }

        // ---------- 1. SplitTree visual-order (same as before) ----------
        for (n, prefersTall, label) in [
            (4, false, "4-cell landscape"), (4, true, "4-cell portrait"),
            (6, false, "6-cell landscape"), (6, true, "6-cell portrait"),
            (9, false, "9-cell square"), (2, false, "2-cell"), (3, false, "3-cell"),
        ] as [(Int, Bool, String)] {
            print("— grid layout: \(label) (N=\(n)) —")
            let views = (0..<n).map { _ in GridSelfTestMockView() }
            let tree = SplitTree<GridSelfTestMockView>.grid(views: views, prefersTall: prefersTall)
            let ordered = visualOrder(tree)
            check("leaf count == N", ordered.count == n, "got \(ordered.count)")
            check("distinct leaves", Set(ordered.map(ObjectIdentifier.init)).count == n)
            let root = tree.root!
            let bbox: [ObjectIdentifier: CGRect] = root.spatial().slots.reduce(into: [:]) { acc, s in
                if case .leaf(let v) = s.node { acc[ObjectIdentifier(v)] = s.bounds }
            }
            var rowMajor = true
            for i in 0..<(ordered.count - 1) {
                let a = bbox[ObjectIdentifier(ordered[i])]!
                let b = bbox[ObjectIdentifier(ordered[i + 1])]!
                let ay = Int(a.minY.rounded()), by = Int(b.minY.rounded())
                if ay > by || (ay == by && a.minX >= b.minX) { rowMajor = false; break }
            }
            check("row-major order", rowMajor)
        }

        // ---------- 2. Reproduce the user's scenario with REAL code ----------
        print("— scenario: tabs → grid → cmd+N across cells —")
        let result = runGridFocusScenario(cellCount: 4, check: check)
        if !result { failures += 1 }

        print("\n\(passes) passed, \(failures) failed")
        return failures == 0 ? 0 : 1
    }

    /// Reproduces the user's exact failure path:
    ///   - build a TerminalController with a grid SplitTree of N real SurfaceViews
    ///   - attach the controller's window (off-screen, never shown)
    ///   - for each cell: post voidFocusGridCell index=k, then inspect state
    private static func runGridFocusScenario(
        cellCount: Int,
        check: (String, @autoclosure () -> Bool, @autoclosure () -> String) -> Void
    ) -> Bool {
        let app = VD.App()
        guard let void_app = app.app else {
            check("VD.App initialised", false, "app.app is nil")
            return false
        }

        // Create N **separate** TerminalControllers to model the user's
        // "multiple tabs" starting state. Each begins with a single fresh
        // SurfaceView in its own window — exactly what happens when the
        // user spawns tabs via cmd+t.
        let tabControllers: [TerminalController] = (0..<cellCount).map { _ in
            TerminalController(app, withBaseConfig: nil)
        }
        // Collect the first (only) surface of each tab — these are the
        // views that flattenTabsToGrid will gather into the grid.
        let surfaces: [VD.SurfaceView] = tabControllers.map { tc in
            tc.surfaceTree.first!
        }

        // Host tab = first one. flattenTabsToGrid will merge everyone
        // else's tree into this one and close their windows.
        let tc = tabControllers[0]
        // Tab every controller's window together so `self.window?.tabGroup`
        // returns a multi-window group (voidDidToggleGridMode requires
        // this to dispatch to flattenTabsToGrid).
        guard let hostWindow = tc.window else {
            check("host TerminalController has window", false, "nil")
            return false
        }
        hostWindow.setFrameOrigin(NSPoint(x: -9999, y: -9999))
        hostWindow.orderFront(nil)
        for sub in tabControllers.dropFirst() {
            guard let w = sub.window else { continue }
            w.setFrameOrigin(NSPoint(x: -9999, y: -9999))
            hostWindow.addTabbedWindow(w, ordered: .above)
        }
        let window = hostWindow
        window.makeKey()
        HeadlessKeyWindowBridge.forceKey(window)

        // Initial render: each tab's content view hierarchy.
        for sub in tabControllers {
            sub.window?.contentView?.layoutSubtreeIfNeeded()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        // Diag: did tab group form?
        print("    [pre-flatten diag] tabGroupWins=\(window.tabGroup?.windows.count ?? 0) tabbingMode=\(window.tabbingMode.rawValue)")

        // Replicate flattenTabsToGrid's end state manually. We can't use
        // the notification path in a headless context because Void's
        // flattenTabsToGrid body is wrapped in `undoManager?.{ ... }`
        // and the self-test process has no AppDelegate-provided undoManager
        // → the optional-chain no-ops the whole block. Direct tree
        // assignment reaches the exact same post-state the user sees.
        let gridTree = SplitTree<VD.SurfaceView>.grid(views: surfaces, prefersTall: false)
        for sub in tabControllers.dropFirst() {
            sub.surfaceTree = .init()
        }
        tc.surfaceTree = gridTree
        tc.focusedSurface = surfaces[0]
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        print("    [post-flatten diag] tree.count=\(Array(tc.surfaceTree).count) tabGroupWins=\(window.tabGroup?.windows.count ?? 0)")

        // Mirror user's starting state after cmd+g: focusTarget (first
        // leaf here) is both focusedSurface AND firstResponder, and
        // reports focused=true. That's the "grid mode → typing works"
        // baseline before they move focus to another cell.
        tc.focusedSurface = surfaces[0]
        _ = window.makeFirstResponder(surfaces[0])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        check("baseline: leaf[0].focused == true (grid initial typing)", surfaces[0].focused,
              "if false even baseline is broken — check isKeyWindow/FR chain")
        print("    [baseline diag] isKeyWindow=\(window.isKeyWindow) leaf0.isFR=\(surfaces[0].isFirstResponder) leaf0.focused=\(surfaces[0].focused)")

        // Now the user-reported failure: cmd+N moves to another cell.
        // Iterate cells 2..N; each transition must: set focusedSurface,
        // move firstResponder, AND bring libvoid's focused flag true for
        // the target while the old cell goes false.
        var allOK = true
        for idx in 2...cellCount {
            let target = surfaces[idx - 1]
            NotificationCenter.default.post(
                name: VD.Notification.voidFocusGridCell,
                object: surfaces[0],  // notification.object = any tree member
                userInfo: [VD.Notification.GridCellIndexKey: idx]
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))

            let fr = window.firstResponder
            let frMatches = (fr as? VD.SurfaceView) === target
            let fsMatches = tc.focusedSurface === target
            let targetFocused = target.focused

            print("    [diag] cmd+\(idx) target=leaf[\(idx-1)] isKey=\(window.isKeyWindow) inHier=\(target.superview != nil) isFR=\(target.isFirstResponder) focused=\(targetFocused)")

            check("cmd+\(idx): focusedSurface → leaf[\(idx-1)]", fsMatches,
                  "got \(String(describing: tc.focusedSurface))")
            check("cmd+\(idx): firstResponder → leaf[\(idx-1)]", frMatches,
                  "got \(String(describing: fr))")
            check("cmd+\(idx): target.focused == true (keys would land)", targetFocused,
                  "libvoid drops keys when surface.focused is false")

            if !(frMatches && fsMatches && targetFocused) { allOK = false }
        }
        return allOK
    }

    private static func visualOrder<V: NSView>(_ tree: SplitTree<V>) -> [V] {
        guard let root = tree.root else { return [] }
        var slots: [(view: V, bounds: CGRect)] = []
        for slot in root.spatial().slots {
            if case .leaf(let view) = slot.node { slots.append((view, slot.bounds)) }
        }
        slots.sort { a, b in
            let ay = Int(a.bounds.minY.rounded()), by = Int(b.bounds.minY.rounded())
            if ay != by { return ay < by }
            return a.bounds.minX < b.bounds.minX
        }
        return slots.map { $0.view }
    }
}

/// Swizzle NSWindow.isKeyWindow to return true for a target window in
/// headless tests. AppKit normally refuses to grant key status to an
/// off-screen window of a non-frontmost .accessory process, which
/// collapses syncFocusToSurfaceTree's gating and yields a false
/// reproduction.
enum HeadlessKeyWindowBridge {
    private static var forcedWindow: NSWindow?
    private static var originalIMP: IMP?
    private static var installed = false

    static func forceKey(_ window: NSWindow) {
        forcedWindow = window
        guard !installed else { return }
        installed = true
        let sel = #selector(getter: NSWindow.isKeyWindow)
        guard let method = class_getInstanceMethod(NSWindow.self, sel) else { return }
        let block: @convention(block) (NSWindow) -> Bool = { win in
            if win === forcedWindow { return true }
            // fall back to default: call the original impl
            if let original = originalIMP {
                typealias Fn = @convention(c) (NSWindow, Selector) -> Bool
                let fn = unsafeBitCast(original, to: Fn.self)
                return fn(win, sel)
            }
            return false
        }
        let newImp = imp_implementationWithBlock(block as Any)
        originalIMP = method_setImplementation(method, newImp)
    }
}

/// Mock NSView that satisfies SplitTree<ViewType>'s constraints — used
/// only for abstract layout assertions. Real scenario uses VD.SurfaceView.
final class GridSelfTestMockView: NSView, Codable, Identifiable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    enum CodingKeys: CodingKey { case id }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        super.init(frame: .zero)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
    }
    override var acceptsFirstResponder: Bool { true }
}
