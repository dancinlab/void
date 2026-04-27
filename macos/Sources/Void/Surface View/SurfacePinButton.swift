import AppKit
import SwiftUI

extension VD {
    /// A small pin toggle in the top-right corner of each pane. Pinned panes
    /// are excluded from the auto-regrid that runs when a new grid cell is
    /// added (see BaseTerminalController.voidDidAddGridCell), so they hold
    /// their layout slot regardless of how many siblings come and go.
    ///
    /// Visibility:
    ///   - Pinned: always visible (filled icon, accent color)
    ///   - Unpinned: visible only on hover (outline icon, low opacity) so
    ///     idle panes stay clean
    struct SurfacePinButton: View {
        @ObservedObject var surfaceView: SurfaceView
        let isSplit: Bool

        @State private var isHovering: Bool = false

        var body: some View {
            // No point in pinning a single full-window surface — re-layouts
            // only run inside split/grid mode.
            if isSplit {
                Button(action: toggle) {
                    Image(systemName: surfaceView.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(
                            surfaceView.isPinned
                                ? Color.accentColor
                                : Color.primary.opacity(isHovering ? 0.7 : 0.0))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Click pointer instead of the surface's default I-beam.
                // macOS 15+ uses pointerStyle; older falls back to NSCursor
                // push/pop in onHover.
                .backport.pointerStyle(.link)
                .onHover { hovering in
                    isHovering = hovering
                    if #available(macOS 15, *) { return }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help(surfaceView.isPinned ? "Unpin pane" : "Pin pane (excludes from auto-regrid)")
            }
        }

        private func toggle() {
            surfaceView.isPinned.toggle()
        }
    }
}
