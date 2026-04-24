// GridSelfTest.swift
//
// --grid-self-test: run the grid visual-order + focus-chain assertions
// inside the Void binary itself, without NSApplicationMain, without any
// terminal window ever being created. Truly headless — sets
// .prohibited activation policy up front so the process never acquires
// a window-server presence.

import AppKit
import Foundation
import VoidKit

/// Minimal NSView subclass that satisfies SplitTree<ViewType>'s generic
/// constraints (NSView & Codable & Identifiable). Used only by the
/// self-test — production grid uses VD.SurfaceView.
final class GridSelfTestMockView: NSView, Codable, Identifiable {
    let id: UUID
    init(id: UUID = UUID()) {
        self.id = id
        super.init(frame: .zero)
    }
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

enum GridSelfTest {
    static func runIfRequested() -> Int32? {
        guard CommandLine.arguments.contains("--grid-self-test") else { return nil }

        // Prohibit activation before any NSApp plumbing brings up a window.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        var passes = 0, failures = 0
        func check(_ label: String, _ cond: @autoclosure () -> Bool, _ note: @autoclosure () -> String = "") {
            if cond() { passes += 1; print("  ✓ \(label)") }
            else      { failures += 1; print("  ✗ \(label)  \(note())") }
        }

        // Part 1 — SplitTree visual-order assertions.
        for (n, prefersTall, label) in [
            (4, false, "4-cell landscape"), (4, true, "4-cell portrait"),
            (6, false, "6-cell landscape"), (6, true, "6-cell portrait"),
            (9, false, "9-cell square"), (2, false, "2-cell"), (3, false, "3-cell"),
        ] as [(Int, Bool, String)] {
            print("— \(label) (N=\(n)) —")
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

        // Part 2 — off-screen NSWindow + makeFirstResponder chain.
        // This verifies the AppKit plumbing the grid-focus fix depends on:
        // given mock views attached to an NSWindow's contentView hierarchy,
        // makeFirstResponder flips firstResponder synchronously.
        print("— window.makeFirstResponder sync —")
        let win = NSWindow(
            contentRect: NSRect(x: -9999, y: -9999, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let a = GridSelfTestMockView()
        let b = GridSelfTestMockView()
        win.contentView?.addSubview(a)
        win.contentView?.addSubview(b)
        let ok1 = win.makeFirstResponder(a)
        check("makeFirstResponder(a) → true", ok1)
        check("firstResponder is a", win.firstResponder === a)
        let ok2 = win.makeFirstResponder(b)
        check("makeFirstResponder(b) → true", ok2)
        check("firstResponder flipped to b", win.firstResponder === b)

        print("\n\(passes) passed, \(failures) failed")
        return failures == 0 ? 0 : 1
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
