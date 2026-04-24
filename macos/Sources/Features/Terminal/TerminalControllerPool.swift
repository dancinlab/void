import AppKit
import VoidKit

/// Warm pool of TerminalControllers pre-instantiated during idle time so
/// explodeIntoTabs doesn't pay the per-window SwiftUI + NSWindow mount
/// cost for each tab it spawns. On a 6-cell explode, the dominant
/// latency used to be the serialised N-1 lazy window loads (~30-100ms
/// each on typical hardware). With a warm pool, take() is O(1) — we
/// hand out pre-loaded controllers and replace their placeholder
/// surface tree with the real subtree.
///
/// Design:
///   - Fixed target size (default 3) maintained in the background.
///   - Each pool entry is a regular TerminalController with a single
///     placeholder VD.SurfaceView; take() hands the controller to the
///     caller, which swaps surfaceTree via replaceSurfaceTree. The
///     placeholder surface is discarded (libvoid frees it on deinit).
///   - Replenishment runs on the main queue (NSWindow init requires
///     main) but deferred via DispatchQueue.main.async with a short
///     delay so it doesn't block user-triggered work.
///   - Safe to call take() before configure() — it just returns nil
///     and callers fall back to eager creation.
@MainActor
final class TerminalControllerPool {
    static let shared = TerminalControllerPool()

    private var pool: [TerminalController] = []
    private var void: VD.App?
    private let targetSize = 3
    private var replenishScheduled = false

    private init() {}

    /// Call once after VD.App is initialised (e.g. in
    /// applicationDidFinishLaunching). Starts the prewarm cycle.
    func configure(with void: VD.App) {
        self.void = void
        scheduleReplenish()
    }

    /// Returns a pre-warmed TerminalController or nil if pool is empty.
    /// Callers must install their real surfaceTree via
    /// replaceSurfaceTree before showing the window — the entry ships
    /// with a placeholder single-surface tree that will be discarded.
    func take() -> TerminalController? {
        let tc = pool.popLast()
        scheduleReplenish()
        return tc
    }

    /// Schedule a main-queue replenish after a short delay so this
    /// doesn't contend with whatever work the caller just triggered.
    private func scheduleReplenish() {
        guard !replenishScheduled else { return }
        guard void != nil else { return }
        replenishScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            guard let self else { return }
            self.replenishScheduled = false
            self.replenishOne()
        }
    }

    /// Add one pool entry, then reschedule if still below target.
    private func replenishOne() {
        guard let void, pool.count < targetSize else { return }
        let tc = TerminalController(void, withBaseConfig: nil)
        _ = tc.window // force lazy window load so it's ready on take()
        pool.append(tc)
        if pool.count < targetSize {
            scheduleReplenish()
        }
    }
}
