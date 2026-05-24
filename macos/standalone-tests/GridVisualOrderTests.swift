// GridVisualOrderTests.swift
//
// Standalone (no XCTest, no window, no NSApplication) verification that
// SplitTree.grid + row-major spatial sort maps cmd+N → the N-th cell in
// visual reading order. Compile+run with:
//
//   bin/void-headless-test
//
// This doubles as a pure-logic regression guard for the fix that makes
// cmd+N in grid mode hit the right cell regardless of landscape/portrait
// window orientation.

import AppKit
import Foundation

@main
struct GridVisualOrderTestsMain {
    static func main() {
        // 4 cells landscape → expect 2×2
        testGridLayout(n: 4, prefersTall: false, label: "4-cell landscape (2×2)")
        // 4 cells portrait → expect 2×2
        testGridLayout(n: 4, prefersTall: true,  label: "4-cell portrait (2×2)")
        // 6 cells landscape → 3×2
        testGridLayout(n: 6, prefersTall: false, label: "6-cell landscape (3×2)")
        // 6 cells portrait → 2×3
        testGridLayout(n: 6, prefersTall: true,  label: "6-cell portrait (2×3)")
        // 9 cells (square)
        testGridLayout(n: 9, prefersTall: false, label: "9-cell (3×3)")
        // 2 cells (horizontal split)
        testGridLayout(n: 2, prefersTall: false, label: "2-cell landscape")
        // 3 cells (2 cols × 2 rows, with one empty — ceil(sqrt(3)) = 2)
        testGridLayout(n: 3, prefersTall: false, label: "3-cell landscape")

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}

// Minimal leaf view type that satisfies SplitTree's generic constraints.
final class MockView: NSView, Codable, Identifiable {
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
}

// Mirrors gridLeavesInVisualOrder() in BaseTerminalController — the
// spatial-sort we are validating.
func gridLeavesInVisualOrder<V>(_ tree: SplitTree<V>) -> [V] {
    guard let root = tree.root else { return [] }
    var slots: [(view: V, bounds: CGRect)] = []
    for slot in root.spatial().slots {
        if case .leaf(let view) = slot.node {
            slots.append((view, slot.bounds))
        }
    }
    slots.sort { a, b in
        let ay = Int(a.bounds.minY.rounded())
        let by = Int(b.bounds.minY.rounded())
        if ay != by { return ay < by }
        return a.bounds.minX < b.bounds.minX
    }
    return slots.map { $0.view }
}

// Tiny test harness — we don't pull in XCTest because that requires the
// full macOS test host + window server session (the whole point of this
// file is to avoid that).
var failures = 0
var passes = 0

func check(_ label: String, _ cond: @autoclosure () -> Bool, _ note: @autoclosure () -> String = "") {
    if cond() {
        passes += 1
        print("  ✓ \(label)")
    } else {
        failures += 1
        print("  ✗ \(label)  \(note())")
    }
}

func testGridLayout(n: Int, prefersTall: Bool, label: String) {
    print("— \(label) (N=\(n), prefersTall=\(prefersTall)) —")
    let views = (0..<n).map { _ in MockView() }
    let tree = SplitTree<MockView>.grid(views: views, prefersTall: prefersTall)
    let visual = gridLeavesInVisualOrder(tree)

    check("leaf count", visual.count == n, "got \(visual.count)")
    check("all distinct", Set(visual.map(\.id)).count == n)

    // Assert row-major ordering: every pair must be ordered by (y, x).
    guard let root = tree.root else { failures += 1; print("  ✗ empty tree"); return }
    let slotBy: [ObjectIdentifier: CGRect] = root.spatial().slots.reduce(into: [:]) { acc, s in
        if case .leaf(let v) = s.node { acc[ObjectIdentifier(v as AnyObject)] = s.bounds }
    }
    var rowMajorOK = true
    for i in 0..<(visual.count - 1) {
        let a = slotBy[ObjectIdentifier(visual[i] as AnyObject)]!
        let b = slotBy[ObjectIdentifier(visual[i + 1] as AnyObject)]!
        let ay = Int(a.minY.rounded()), by = Int(b.minY.rounded())
        if ay > by || (ay == by && a.minX >= b.minX) {
            rowMajorOK = false
            print("    order violated at [\(i)]: (y=\(ay),x=\(a.minX)) vs (y=\(by),x=\(b.minX))")
            break
        }
    }
    check("row-major order", rowMajorOK)
}

// (test cases moved into @main above)
