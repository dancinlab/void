import SwiftUI

/// A single operation within the split tree.
///
/// Rather than binding the split tree (which is immutable), any mutable operations are
/// exposed via this enum to the embedder to handle.
enum TerminalSplitOperation {
    case resize(Resize)
    case drop(Drop)
    /// Atomic multi-divider resize used by Cmd+drag magnetic grid resize.
    /// Applied deepest-path-first so ancestors don't clobber descendant updates.
    case resizeBatch(BatchResize)
    /// Cmd+drag release over another grid cell — exchange the two leaves'
    /// positions in the tree so the panes effectively swap places.
    case swap(Swap)
    /// Cmd+drag release while the cursor was hugging a window edge — pull
    /// the source out of its current slot and reshape the root so the source
    /// fills the entire half on the snapped side (top/bottom/left/right).
    case edgeSnap(EdgeSnap)

    struct Resize {
        let node: SplitTree<VD.SurfaceView>.Node
        let ratio: Double
    }

    struct Drop {
        /// The surface being dragged.
        let payload: VD.SurfaceView

        /// The surface it was dragged onto
        let destination: VD.SurfaceView

        /// The zone it was dropped to determine how to split the destination.
        let zone: TerminalSplitDropZone
    }

    struct BatchResize {
        let items: [Item]
        struct Item {
            let path: SplitTree<VD.SurfaceView>.Path
            let ratio: Double
        }
    }

    struct Swap {
        let source: VD.SurfaceView
        let destination: VD.SurfaceView
    }

    struct EdgeSnap {
        let source: VD.SurfaceView
        let zone: TerminalSplitDropZone
    }
}

struct TerminalSplitTreeView: View {
    let tree: SplitTree<VD.SurfaceView>
    let action: (TerminalSplitOperation) -> Void

    @EnvironmentObject private var void: VD.App
    @StateObject private var magnetic = MagneticDragController()
    @StateObject private var cmdMonitor = CmdModifierMonitor()

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            GeometryReader { geo in
                ZStack {
                    TerminalSplitSubtreeView(
                        node: node,
                        isRoot: node == tree.root,
                        magnetic: magnetic,
                        rootTree: tree,
                        rootSize: geo.size,
                        action: action)
                    .environmentObject(cmdMonitor)
                    // This is necessary because we can't rely on SwiftUI's implicit
                    // structural identity to detect changes to this view. Due to
                    // the tree structure of splits it could result in bad behaviors.
                    // See: https://github.com/ghostty-org/ghostty/issues/7546
                    .id(node.structuralIdentity)

                    if magnetic.snapshot != nil {
                        MagneticPreviewOverlay(
                            controller: magnetic,
                            resizePreviewEnabled: void.config.splitDividerResize)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: MagneticDragController.coordinateSpaceName)
            }
        }
    }
}

private struct TerminalSplitSubtreeView: View {
    @EnvironmentObject var void: VD.App

    let node: SplitTree<VD.SurfaceView>.Node
    var isRoot: Bool = false
    let magnetic: MagneticDragController
    let rootTree: SplitTree<VD.SurfaceView>
    let rootSize: CGSize
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        switch node {
        case .leaf(let leafView):
            TerminalSplitLeaf(
                surfaceView: leafView,
                isSplit: !isRoot,
                magnetic: magnetic,
                rootTree: rootTree,
                rootSize: rootSize,
                action: action)

        case .split(let split):
            let splitViewDirection: SplitViewDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            SplitView(
                splitViewDirection,
                .init(get: {
                    CGFloat(split.ratio)
                }, set: {
                    action(.resize(.init(node: node, ratio: $0)))
                }),
                dividerColor: void.config.splitDividerColor,
                resizeIncrements: .init(width: 1, height: 1),
                resizeEnabled: void.config.splitDividerResize,
                left: {
                    TerminalSplitSubtreeView(
                        node: split.left,
                        magnetic: magnetic,
                        rootTree: rootTree,
                        rootSize: rootSize,
                        action: action)
                },
                right: {
                    TerminalSplitSubtreeView(
                        node: split.right,
                        magnetic: magnetic,
                        rootTree: rootTree,
                        rootSize: rootSize,
                        action: action)
                },
                onEqualize: {
                    guard let surface = node.leftmostLeaf().surface else { return }
                    void.splitEqualize(surface: surface)
                }
            )
        }
    }
}

private struct TerminalSplitLeaf: View {
    @ObservedObject var surfaceView: VD.SurfaceView
    let isSplit: Bool
    let magnetic: MagneticDragController
    let rootTree: SplitTree<VD.SurfaceView>
    let rootSize: CGSize
    let action: (TerminalSplitOperation) -> Void

    @FocusedValue(\.voidSurfaceView) private var focusedSurface
    @EnvironmentObject private var cmdMonitor: CmdModifierMonitor
    @EnvironmentObject private var void: VD.App

    @State private var dropState: DropState = .idle
    @State private var isSelfDragging: Bool = false
    @State private var hovered: Bool = false

    /// Show the focus indicator only inside a split/grid where it carries
    /// information — a single full-window surface is unambiguously focused.
    private var isFocusedLeaf: Bool {
        isSplit && focusedSurface === surfaceView
    }

    /// Per-pane top-center label showing this leaf's working directory.
    /// Only rendered inside a split/grid — a single full-window surface
    /// already shows its title in the window titlebar.
    /// When this pane's bell is active (e.g. a TUI like Claude Code rang
    /// the bell on turn completion, or shell integration fired
    /// notify-on-command-finish for an unfocused pane), a small green
    /// "live" dot appears so the user can spot which cell finished at a
    /// glance. Bell auto-clears when this surface gains focus, so the dot
    /// disappears the moment the user clicks in.
    @ViewBuilder private var pwdLabel: some View {
        if isSplit {
            let pwd = surfaceView.pwd ?? ""
            let pathLabel = pwd.isEmpty ? "" : VoidPathTitleStyle.format(pwd)
            let bell = surfaceView.bell
            if bell || !pathLabel.isEmpty {
                HStack(spacing: 6) {
                    if bell {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .shadow(color: Color.green.opacity(0.6), radius: 2)
                    }
                    if !pathLabel.isEmpty {
                        Text(pathLabel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .padding(.top, 6)
                .allowsHitTesting(false)
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VD.InspectableSurface(
                surfaceView: surfaceView,
                isSplit: isSplit)
            .background {
                // If we're dragging ourself, we hide the entire drop zone. This makes
                // it so that a released drop animates back to its source properly
                // so it is a proper invalid drop zone.
                if !isSelfDragging {
                    Color.clear
                        .onDrop(of: [.voidSurfaceId], delegate: SplitDropDelegate(
                            dropState: $dropState,
                            viewSize: geometry.size,
                            destinationSurface: surfaceView,
                            action: action
                        ))
                }
            }
            .overlay {
                // Visible focus ring for split/grid leaves. The cursor blink
                // alone is too subtle when there are 4+ cells on screen.
                if isFocusedLeaf {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
                // Subtle "movable" hint: only renders when Cmd is held AND this
                // is the focused pane AND mouse is hovering it. Cmd state is
                // event-driven (no polling); the body skips this branch entirely
                // when Cmd is released, so the cost is zero outside drag intent.
                if cmdMonitor.isHeld && isFocusedLeaf && hovered {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .padding(3)
                        .allowsHitTesting(false)
                }
                if !isSelfDragging, case .dropping(let zone) = dropState {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovered = $0 }
            .overlay(alignment: .top) { pwdLabel }
            .onPreferenceChange(VD.DraggingSurfaceKey.self) { value in
                isSelfDragging = value == surfaceView.id
                if isSelfDragging {
                    dropState = .idle
                }
            }
            // Cmd+drag = magnetic grid resize. Runs simultaneously so terminal
            // selection (plain drag) and surface clicks are unaffected.
            .simultaneousGesture(magneticDragGesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Terminal pane")
        }
    }

    private var magneticDragGesture: some Gesture {
        DragGesture(
            minimumDistance: MagneticDragController.activationDistance,
            coordinateSpace: .named(MagneticDragController.coordinateSpaceName)
        )
        .onChanged { value in
            // Only act when Cmd is held — checked once at activation. Without
            // Cmd, we silently no-op so plain drags fall through to the surface.
            if magnetic.snapshot == nil {
                guard NSEvent.modifierFlags.contains(.command) else { return }
                let started = magnetic.begin(
                    at: value.startLocation,
                    translation: value.translation,
                    in: rootTree,
                    rootSize: rootSize)
                guard started else { return }
            }
            // Deferred commit: only update the overlay state, do NOT touch the
            // surface tree. This avoids per-frame Metal pipeline rebuilds.
            magnetic.update(translation: value.translation, location: value.location)
        }
        .onEnded { _ in
            guard let snap = magnetic.snapshot else { return }
            // Drop priority — first match wins:
            //   1. cursor in window edge band → edge snap (source fills that
            //      half, layout reshapes around it)
            //   2. cursor over another cell → swap (positions exchange)
            //   3. `split-divider-resize` opted in → magnetic resize commit
            //   4. else → no-op (hint-only, locked layout)
            let source = snap.sourceView
            if let source, let zone = magnetic.edgeSnap {
                action(.edgeSnap(.init(source: source, zone: zone.toDropZone)))
            } else if let source, let target = magnetic.hoveredView, source !== target {
                action(.swap(.init(source: source, destination: target)))
            } else if void.config.splitDividerResize {
                let items = magnetic.resizeOps()
                if !items.isEmpty {
                    action(.resizeBatch(.init(items: items)))
                }
            }
            magnetic.end()
        }
    }

    private enum DropState: Equatable {
        case idle
        case dropping(TerminalSplitDropZone)
    }

    private struct SplitDropDelegate: DropDelegate {
        @Binding var dropState: DropState
        let viewSize: CGSize
        let destinationSurface: VD.SurfaceView
        let action: (TerminalSplitOperation) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.voidSurfaceId])
        }

        func dropEntered(info: DropInfo) {
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            // For some reason dropUpdated is sent after performDrop is called
            // and we don't want to reset our drop zone to show it so we have
            // to guard on the state here.
            guard case .dropping = dropState else { return DropProposal(operation: .forbidden) }
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            dropState = .idle
        }

        func performDrop(info: DropInfo) -> Bool {
            let zone = TerminalSplitDropZone.calculate(at: info.location, in: viewSize)
            dropState = .idle

            // Load the dropped surface asynchronously using Transferable
            let providers = info.itemProviders(for: [.voidSurfaceId])
            guard let provider = providers.first else { return false }

            // Capture action before the async closure
            _ = provider.loadTransferable(type: VD.SurfaceView.self) { [weak destinationSurface] result in
                switch result {
                case .success(let sourceSurface):
                    DispatchQueue.main.async {
                        // Don't allow dropping on self
                        guard let destinationSurface else { return }
                        guard sourceSurface !== destinationSurface else { return }
                        action(.drop(.init(payload: sourceSurface, destination: destinationSurface, zone: zone)))
                    }

                case .failure:
                    break
                }
            }

            return true
        }
    }
}

enum TerminalSplitDropZone: String, Equatable {
    case top
    case bottom
    case left
    case right

    /// Determines which drop zone the cursor is in based on proximity to edges.
    ///
    /// Divides the view into four triangular regions by drawing diagonals from
    /// corner to corner. The drop zone is determined by which edge the cursor
    /// is closest to, creating natural triangular hit regions for each side.
    static func calculate(at point: CGPoint, in size: CGSize) -> TerminalSplitDropZone {
        let relX = point.x / size.width
        let relY = point.y / size.height

        let distToLeft = relX
        let distToRight = 1 - relX
        let distToTop = relY
        let distToBottom = 1 - relY

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        if minDist == distToLeft { return .left }
        if minDist == distToRight { return .right }
        if minDist == distToTop { return .top }
        return .bottom
    }

    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let overlayColor = Color.accentColor.opacity(0.3)

        switch self {
        case .top:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
                Spacer()
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
            }
        case .left:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
            }
        }
    }
}

// MARK: - Magnetic Cmd+Drag Resize
//
// Cmd+drag from any pane = magnetic grid resize.
// • Primary handle = nearest split divider (matching the drag axis) to the
//   cursor's start position.
// • Secondaries = other splits with the same direction whose splitting line
//   sits within `snapRadius` of the primary's line at drag start. They move
//   with the primary, so dragging the right side of one cell pulls the whole
//   column.
// • Resize ops are batched and applied atomically (deepest path first) so
//   ancestor splits don't clobber descendant ratios.

/// Tracks whether the Cmd key is currently held. Driven by an NSEvent local
/// monitor on `.flagsChanged` — fires only on modifier changes, not per frame
/// or per mouse move, so the steady-state cost is zero.
@MainActor
final class CmdModifierMonitor: ObservableObject {
    @Published private(set) var isHeld: Bool = NSEvent.modifierFlags.contains(.command)
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let held = event.modifierFlags.contains(.command)
            if let self, self.isHeld != held {
                self.isHeld = held
            }
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

@MainActor
final class MagneticDragController: ObservableObject {
    static let coordinateSpaceName = "split-tree-root"
    static let activationDistance: CGFloat = 6
    static let snapRadius: CGFloat = 12
    static let minRatio: Double = 0.05
    static let maxRatio: Double = 0.95
    /// Distance from the window edge at which we surface the half-window snap hint.
    /// Sized for typical drag distances: in a 1200pt window with a 50/50 split,
    /// the divider starts ~600pt from each edge, so a generous band is needed
    /// for the hint to feel reachable rather than only firing at the very edge.
    static let edgeSnapThreshold: CGFloat = 120

    /// Which window edge the drag is hugging — only ever the two parallel to the
    /// drag axis, so corners/diagonals are unrepresentable by construction.
    enum EdgeSnapZone {
        case top, bottom, left, right

        var toDropZone: TerminalSplitDropZone {
            switch self {
            case .top:    return .top
            case .bottom: return .bottom
            case .left:   return .left
            case .right:  return .right
            }
        }
    }

    struct Handle {
        let path: SplitTree<VD.SurfaceView>.Path
        let initialRatio: Double
        let parentBounds: CGRect
    }

    /// A leaf cell's bounds in root coords, paired with its view for identity
    /// comparison. Captured at drag start so cursor-over-cell detection during
    /// the drag is a flat lookup — the tree doesn't mutate mid-drag.
    struct LeafSlot {
        let view: VD.SurfaceView
        let bounds: CGRect
    }

    struct Snapshot {
        let direction: SplitTree<VD.SurfaceView>.Direction
        let primary: Handle
        let secondaries: [Handle]
        let rootSize: CGSize
        let leafSlots: [LeafSlot]
        /// The leaf the drag started over. Excluded from hover highlighting so
        /// the user sees a hint only when hovering OVER ANOTHER cell.
        let sourceView: VD.SurfaceView?
    }

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var translation: CGSize = .zero
    /// Cursor position in the root coord space, updated every drag tick. Used
    /// for edge-snap detection so the hint follows the mouse, not the divider —
    /// the user's intuition is "near edge = hint", not "divider near edge".
    @Published private(set) var cursorLocation: CGPoint = .zero

    var allHandles: [Handle] {
        guard let s = snapshot else { return [] }
        return [s.primary] + s.secondaries
    }

    /// Begins a magnetic drag if any matching split divider exists for the drag axis.
    /// Returns true on success. Drag axis is inferred from the initial translation.
    func begin(
        at point: CGPoint,
        translation: CGSize,
        in tree: SplitTree<VD.SurfaceView>,
        rootSize: CGSize
    ) -> Bool {
        guard let root = tree.root else { return false }
        let dx = abs(translation.width)
        let dy = abs(translation.height)
        // Horizontal motion → grab a horizontal split (vertical line moves left/right).
        let direction: SplitTree<VD.SurfaceView>.Direction = (dx >= dy) ? .horizontal : .vertical

        let spatial = root.spatial(within: rootSize)
        var candidates: [Handle] = []
        var leafSlots: [LeafSlot] = []
        var sourceView: VD.SurfaceView?
        for slot in spatial.slots {
            switch slot.node {
            case .split(let split) where split.direction == direction:
                guard let path = root.path(to: slot.node) else { continue }
                candidates.append(Handle(
                    path: path,
                    initialRatio: split.ratio,
                    parentBounds: slot.bounds))
            case .leaf(let view):
                leafSlots.append(LeafSlot(view: view, bounds: slot.bounds))
                if slot.bounds.contains(point) {
                    sourceView = view
                }
            default:
                continue
            }
        }
        guard !candidates.isEmpty else { return false }

        func lineCoord(_ h: Handle) -> CGFloat {
            switch direction {
            case .horizontal: return h.parentBounds.minX + h.parentBounds.width * h.initialRatio
            case .vertical:   return h.parentBounds.minY + h.parentBounds.height * h.initialRatio
            }
        }
        // Restrict candidates to those whose orthogonal extent contains the cursor —
        // otherwise a horizontal split far above the cursor could be grabbed.
        let containing = candidates.filter { h in
            switch direction {
            case .horizontal:
                return point.y >= h.parentBounds.minY && point.y <= h.parentBounds.maxY
            case .vertical:
                return point.x >= h.parentBounds.minX && point.x <= h.parentBounds.maxX
            }
        }
        let pool = containing.isEmpty ? candidates : containing
        let probe: CGFloat = (direction == .horizontal) ? point.x : point.y
        guard let primary = pool.min(by: { abs(lineCoord($0) - probe) < abs(lineCoord($1) - probe) }) else {
            return false
        }
        let primaryCoord = lineCoord(primary)
        let secondaries = candidates.filter { h in
            // Skip the primary itself
            guard h.path.path != primary.path.path else { return false }
            return abs(lineCoord(h) - primaryCoord) <= Self.snapRadius
        }

        snapshot = Snapshot(
            direction: direction,
            primary: primary,
            secondaries: secondaries,
            rootSize: rootSize,
            leafSlots: leafSlots,
            sourceView: sourceView)
        self.translation = translation
        self.cursorLocation = point
        return true
    }

    func update(translation: CGSize, location: CGPoint) {
        self.translation = translation
        self.cursorLocation = location
    }

    func end() {
        snapshot = nil
        translation = .zero
    }

    /// Compute the batch resize items for the current translation. Deepest paths
    /// first so when applied sequentially via path-replace, ancestor updates
    /// don't overwrite descendant in-progress changes.
    func resizeOps() -> [TerminalSplitOperation.BatchResize.Item] {
        guard let snap = snapshot else { return [] }
        let translationCoord: CGFloat = (snap.direction == .horizontal) ? translation.width : translation.height
        let primaryStart: CGFloat = {
            switch snap.direction {
            case .horizontal:
                return snap.primary.parentBounds.minX + snap.primary.parentBounds.width * snap.primary.initialRatio
            case .vertical:
                return snap.primary.parentBounds.minY + snap.primary.parentBounds.height * snap.primary.initialRatio
            }
        }()
        let target = primaryStart + translationCoord

        var items: [TerminalSplitOperation.BatchResize.Item] = []
        for h in allHandles {
            let extent: CGFloat = (snap.direction == .horizontal) ? h.parentBounds.width : h.parentBounds.height
            let origin: CGFloat = (snap.direction == .horizontal) ? h.parentBounds.minX : h.parentBounds.minY
            guard extent > 0 else { continue }
            let raw = Double((target - origin) / extent)
            let ratio = max(Self.minRatio, min(Self.maxRatio, raw))
            items.append(.init(path: h.path, ratio: ratio))
        }
        // Deepest path first
        items.sort { $0.path.path.count > $1.path.path.count }
        return items
    }

    /// Position of the dragged splitting line in root coords (X for horizontal split, Y for vertical).
    var previewLineCoord: CGFloat? {
        guard let snap = snapshot else { return nil }
        let start: CGFloat
        let delta: CGFloat
        switch snap.direction {
        case .horizontal:
            start = snap.primary.parentBounds.minX + snap.primary.parentBounds.width * snap.primary.initialRatio
            delta = translation.width
        case .vertical:
            start = snap.primary.parentBounds.minY + snap.primary.parentBounds.height * snap.primary.initialRatio
            delta = translation.height
        }
        return start + delta
    }

    /// Bounds of the OTHER leaf cell the cursor is currently over, or nil if
    /// the cursor is still in (or returned to) the source cell, or outside any
    /// cell. Drives the white outline that signals "this cell is the hover
    /// target". Source cell is excluded so the user only sees a hint when
    /// they've moved over a different pane.
    var hoveredLeafBounds: CGRect? {
        hoveredLeafSlot?.bounds
    }

    /// The OTHER leaf cell's view the cursor is currently over, or nil. Used
    /// at drag end to decide whether to perform a swap commit.
    var hoveredView: VD.SurfaceView? {
        hoveredLeafSlot?.view
    }

    private var hoveredLeafSlot: LeafSlot? {
        guard let snap = snapshot else { return nil }
        for slot in snap.leafSlots where slot.bounds.contains(cursorLocation) {
            if slot.view === snap.sourceView { return nil }
            return slot
        }
        return nil
    }

    /// Edge of the root view the cursor is currently within `edgeSnapThreshold`
    /// of, or nil. Cursor-driven (not divider-driven) so the hint surfaces as
    /// soon as the user's pointer hugs an edge, regardless of where along the
    /// drag axis the divider currently sits. Axis-locked: horizontal splits
    /// can only hit `.left`/`.right`, vertical splits only `.top`/`.bottom`.
    var edgeSnap: EdgeSnapZone? {
        guard let snap = snapshot else { return nil }
        let p = cursorLocation
        switch snap.direction {
        case .horizontal:
            if p.x <= Self.edgeSnapThreshold { return .left }
            if p.x >= snap.rootSize.width - Self.edgeSnapThreshold { return .right }
        case .vertical:
            if p.y <= Self.edgeSnapThreshold { return .top }
            if p.y >= snap.rootSize.height - Self.edgeSnapThreshold { return .bottom }
        }
        return nil
    }

    /// Fraction of the root that the source pane will occupy after an edge
    /// snap commit. Mirrors the cols/rows math in `splitDidEdgeSnap` so the
    /// preview hint matches the actual layout — without this the hint would
    /// always render as a 50% slab even when the result is, say, 1/3.
    func edgeSnapSourceFraction(zone: EdgeSnapZone) -> Double {
        guard let snap = snapshot else { return 0.5 }
        let totalCount = snap.leafSlots.count
        guard totalCount >= 2 else { return 0.5 }
        let prefersTall = snap.rootSize.height > snap.rootSize.width
        let major = max(2, Int(ceil(Double(totalCount).squareRoot())))
        let cols: Int
        let rows: Int
        if prefersTall {
            rows = major
            cols = max(1, Int(ceil(Double(totalCount) / Double(rows))))
        } else {
            cols = major
            rows = max(1, Int(ceil(Double(totalCount) / Double(cols))))
        }
        switch zone {
        case .top, .bottom: return 1.0 / Double(rows)
        case .left, .right: return 1.0 / Double(cols)
        }
    }
}

private struct MagneticPreviewOverlay: View {
    @ObservedObject var controller: MagneticDragController
    /// Render the resize preview visuals (accent rectangles, accent divider
    /// band, dotted preview line). When false, only the white hover/edge
    /// hints render — matching the locked-resize default UX where the
    /// dotted line would falsely promise a resize.
    let resizePreviewEnabled: Bool

    var body: some View {
        GeometryReader { geo in
            if let snap = controller.snapshot, let coord = controller.previewLineCoord {
                ZStack(alignment: .topLeading) {
                    if resizePreviewEnabled {
                        // Stroked rectangles outlining the future bounds of the two
                        // halves of every affected split — the user sees where panes
                        // will end up without us mutating the tree mid-drag.
                        ForEach(Array(controller.allHandles.enumerated()), id: \.offset) { _, h in
                            let (a, b) = subBounds(for: h, at: coord, direction: snap.direction, in: geo.size)
                            rectOutline(a)
                            rectOutline(b)
                        }
                        // Highlight the moving divider line itself (a thin accent band).
                        ForEach(Array(controller.allHandles.enumerated()), id: \.offset) { _, h in
                            highlightBand(for: h, at: coord, direction: snap.direction, in: geo.size)
                        }
                        // Dotted full-extent preview line in the orthogonal axis.
                        previewLine(coord: coord, direction: snap.direction, in: geo.size)
                    }
                    // Edge snap takes priority over cell hover — when the
                    // cursor hugs a window edge the user's intent is
                    // "fill that half", not "swap with the cell underneath".
                    // Showing both at once would be ambiguous, so we pick
                    // one hint based on the same priority `onEnded` uses.
                    if let zone = controller.edgeSnap {
                        edgeSnapHint(zone: zone, in: geo.size)
                    } else if let bounds = controller.hoveredLeafBounds {
                        cellHoverHint(bounds: bounds)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellHoverHint(bounds: CGRect) -> some View {
        Path { p in p.addRect(bounds) }
            .stroke(Color.white.opacity(0.95), lineWidth: 3)
    }

    @ViewBuilder
    private func edgeSnapHint(
        zone: MagneticDragController.EdgeSnapZone,
        in size: CGSize
    ) -> some View {
        let f = controller.edgeSnapSourceFraction(zone: zone)
        let rect: CGRect = {
            switch zone {
            case .top:    return CGRect(x: 0, y: 0, width: size.width, height: size.height * f)
            case .bottom: return CGRect(x: 0, y: size.height * (1 - f), width: size.width, height: size.height * f)
            case .left:   return CGRect(x: 0, y: 0, width: size.width * f, height: size.height)
            case .right:  return CGRect(x: size.width * (1 - f), y: 0, width: size.width * f, height: size.height)
            }
        }()
        Path { p in p.addRect(rect) }
            .stroke(Color.white.opacity(0.95), lineWidth: 3)
    }

    /// Computes the future bounds of a split's two halves at the given line coord.
    /// Clips to root size so we never draw past the window.
    private func subBounds(
        for h: MagneticDragController.Handle,
        at coord: CGFloat,
        direction: SplitTree<VD.SurfaceView>.Direction,
        in size: CGSize
    ) -> (CGRect, CGRect) {
        let pb = h.parentBounds
        switch direction {
        case .horizontal:
            let clamped = max(pb.minX + 1, min(pb.maxX - 1, coord))
            let left = CGRect(x: pb.minX, y: pb.minY,
                              width: clamped - pb.minX, height: pb.height)
            let right = CGRect(x: clamped, y: pb.minY,
                               width: pb.maxX - clamped, height: pb.height)
            return (left.intersection(CGRect(origin: .zero, size: size)),
                    right.intersection(CGRect(origin: .zero, size: size)))
        case .vertical:
            let clamped = max(pb.minY + 1, min(pb.maxY - 1, coord))
            let top = CGRect(x: pb.minX, y: pb.minY,
                             width: pb.width, height: clamped - pb.minY)
            let bottom = CGRect(x: pb.minX, y: clamped,
                                width: pb.width, height: pb.maxY - clamped)
            return (top.intersection(CGRect(origin: .zero, size: size)),
                    bottom.intersection(CGRect(origin: .zero, size: size)))
        }
    }

    @ViewBuilder
    private func rectOutline(_ rect: CGRect) -> some View {
        if rect.width > 0 && rect.height > 0 {
            Path { p in p.addRect(rect) }
                .stroke(Color.accentColor.opacity(0.85), lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private func highlightBand(
        for h: MagneticDragController.Handle,
        at coord: CGFloat,
        direction: SplitTree<VD.SurfaceView>.Direction,
        in size: CGSize
    ) -> some View {
        let band: CGFloat = 2
        switch direction {
        case .horizontal:
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: band, height: h.parentBounds.height)
                .position(x: coord, y: h.parentBounds.midY)
        case .vertical:
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: h.parentBounds.width, height: band)
                .position(x: h.parentBounds.midX, y: coord)
        }
    }

    @ViewBuilder
    private func previewLine(
        coord: CGFloat,
        direction: SplitTree<VD.SurfaceView>.Direction,
        in size: CGSize
    ) -> some View {
        let dash: [CGFloat] = [4, 4]
        switch direction {
        case .horizontal:
            Path { p in
                p.move(to: CGPoint(x: coord, y: 0))
                p.addLine(to: CGPoint(x: coord, y: size.height))
            }
            .stroke(Color.accentColor.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: dash))
        case .vertical:
            Path { p in
                p.move(to: CGPoint(x: 0, y: coord))
                p.addLine(to: CGPoint(x: size.width, y: coord))
            }
            .stroke(Color.accentColor.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: dash))
        }
    }
}
