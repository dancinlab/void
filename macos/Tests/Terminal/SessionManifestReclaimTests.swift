import Foundation
import Testing
@testable import VoidApp

/// Tests for `SessionManifest.ringsToReclaim(previousLive:currentLive:isTerminating:)`,
/// the pure decision behind reclaiming a closed surface's persist ring during a
/// running session (instead of waiting for launch-time auto-GC).
///
/// Unlike the triage suite, this exercises the REAL production function directly
/// — it was extracted specifically to be side-effect-free and testable. The
/// file-system deletion (`deleteRings`) stays private/best-effort; the contract
/// that matters for data safety lives entirely in this decision.
@Suite
struct SessionManifestReclaimTests {
    private let a = "AAAAAAAA-0000-0000-0000-000000000001"
    private let b = "BBBBBBBB-0000-0000-0000-000000000002"
    private let c = "CCCCCCCC-0000-0000-0000-000000000003"
    private let d = "DDDDDDDD-0000-0000-0000-000000000004"

    @Test("A surface gone from all windows this session is reclaimed")
    func normalClose() {
        let closed = SessionManifest.ringsToReclaim(
            previousLive: [a, b, c], currentLive: [a, b], isTerminating: false)
        #expect(closed == [c])
    }

    @Test("Multiple closes in one refresh are all reclaimed")
    func multipleCloses() {
        let closed = SessionManifest.ringsToReclaim(
            previousLive: [a, b, c, d], currentLive: [a], isTerminating: false)
        #expect(closed == [b, c, d])
    }

    @Test("No change reclaims nothing")
    func steadyState() {
        let closed = SessionManifest.ringsToReclaim(
            previousLive: [a, b], currentLive: [a, b], isTerminating: false)
        #expect(closed.isEmpty)
    }

    @Test("Opening surfaces never reclaims")
    func opensOnly() {
        let closed = SessionManifest.ringsToReclaim(
            previousLive: [a], currentLive: [a, b], isTerminating: false)
        #expect(closed.isEmpty)
    }

    // MARK: - Data-safety invariants

    @Test("Terminating preserves all live rings (cold-restore on quit/restart)")
    func terminatingPreserves() {
        // The macOS-restart case: every window torn down, yet nothing reclaimed.
        let closed = SessionManifest.ringsToReclaim(
            previousLive: [a, b, c], currentLive: [], isTerminating: true)
        #expect(closed.isEmpty)
    }

    @Test("First refresh (empty previous) never deletes prior-session rings")
    func launchSafety() {
        // At launch `liveLastSet` is empty, so restored/older rings present on
        // disk but absent from the live set are never deleted by this path.
        let closed = SessionManifest.ringsToReclaim(
            previousLive: [], currentLive: [a, b], isTerminating: false)
        #expect(closed.isEmpty)
    }

    @Test("A surface migrating between windows is not a close")
    func migrationIsNotClose() {
        // Migration scans all windows, so the surface stays in `currentLive`.
        let closed = SessionManifest.ringsToReclaim(
            previousLive: [a, b], currentLive: [a, b], isTerminating: false)
        #expect(closed.isEmpty)
    }
}
