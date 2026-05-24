import Foundation
import Testing
@testable import VoidApp

/// Tests for `SessionManifest.triage(restoredUUIDs:)` partition logic.
///
/// Note on test surface: production `triage(restoredUUIDs:)` reads the prior
/// snapshot from `SessionManifest.previousSession` and the on-disk ring set
/// from a private file-system helper. Neither is injectable, and the manifest
/// is hard-coded to `~/.void/sessions/last.json` so swapping a temp directory
/// would destroy the developer's real session state.
///
/// To exercise the partition contract without mutating production code or the
/// user's home directory, this suite tests:
///   1. The `Triage` value type directly (construction + property access), and
///   2. A test-local `partition(prev:restored:disk:)` helper that mirrors the
///      math in `SessionManifest.triage` line-for-line. Any change to the
///      production math must be reflected here, keeping the spec aligned.
///
/// Production reference (SessionManifest.swift, triage(restoredUUIDs:)):
///   let recovered    = prev.intersection(restoredUUIDs)
///   let topologyLost = prev.subtracting(restoredUUIDs).intersection(disk)
///   let staleOrphans = disk.subtracting(prev)
@Suite
struct SessionManifestTriageTests {
    /// Mirror of the production partition math. Must stay in lockstep with
    /// `SessionManifest.triage(restoredUUIDs:)`.
    private func partition(
        prev: Set<String>,
        restored: Set<String>,
        disk: Set<String>
    ) -> SessionManifest.Triage {
        let recovered = prev.intersection(restored)
        let topologyLost = prev.subtracting(restored).intersection(disk)
        let staleOrphans = disk.subtracting(prev)
        return SessionManifest.Triage(
            recovered: recovered,
            topologyLost: topologyLost,
            staleOrphans: staleOrphans
        )
    }

    // MARK: - Triage value type

    @Test func triageHoldsAssignedSets() {
        let t = SessionManifest.Triage(
            recovered: ["A"],
            topologyLost: ["B"],
            staleOrphans: ["C"]
        )
        #expect(t.recovered == ["A"])
        #expect(t.topologyLost == ["B"])
        #expect(t.staleOrphans == ["C"])
    }

    // MARK: - Partition cases

    @Test func emptyInputsYieldEmptyPartitions() {
        let t = partition(prev: [], restored: [], disk: [])
        #expect(t.recovered.isEmpty)
        #expect(t.topologyLost.isEmpty)
        #expect(t.staleOrphans.isEmpty)
    }

    @Test func fullyRestoredHappyPath() {
        // prev = disk = restored → every UUID lands in `recovered`.
        let all: Set<String> = ["uuid-A", "uuid-B", "uuid-C"]
        let t = partition(prev: all, restored: all, disk: all)
        #expect(t.recovered == all)
        #expect(t.topologyLost.isEmpty)
        #expect(t.staleOrphans.isEmpty)
    }

    @Test func silentLossWhenRestoredIsEmpty() {
        // prev = disk, restored = ∅ → AppKit flush-lag loss: ring file exists
        // on disk, prior manifest names it, but no SurfaceView claimed it.
        let all: Set<String> = ["uuid-A", "uuid-B"]
        let t = partition(prev: all, restored: [], disk: all)
        #expect(t.recovered.isEmpty)
        #expect(t.topologyLost == all)
        #expect(t.staleOrphans.isEmpty)
    }

    @Test func staleOrphansWhenPrevIsEmpty() {
        // prev = ∅, disk has rings → orphans from sessions older than the
        // last one; safe to GC.
        let disk: Set<String> = ["uuid-A", "uuid-B", "uuid-C"]
        let t = partition(prev: [], restored: [], disk: disk)
        #expect(t.recovered.isEmpty)
        #expect(t.topologyLost.isEmpty)
        #expect(t.staleOrphans == disk)
    }

    @Test func mixedThreeWayPartition() {
        // prev = {A,B}, restored = {A}, disk = {A,B,C}
        //   recovered    = {A}     (prev ∩ restored)
        //   topologyLost = {B}     (prev - restored, intersected with disk)
        //   staleOrphans = {C}     (disk - prev)
        let prev: Set<String> = ["A", "B"]
        let restored: Set<String> = ["A"]
        let disk: Set<String> = ["A", "B", "C"]
        let t = partition(prev: prev, restored: restored, disk: disk)
        #expect(t.recovered == ["A"])
        #expect(t.topologyLost == ["B"])
        #expect(t.staleOrphans == ["C"])
    }

    @Test func topologyLostRequiresDiskPresence() {
        // A UUID in `prev` but missing from BOTH `restored` and `disk` is NOT
        // topology-loss — the ring file is also gone, so there's nothing to
        // recover. Production math intersects (prev - restored) with disk.
        let prev: Set<String> = ["A", "B"]
        let restored: Set<String> = []
        let disk: Set<String> = ["A"]  // B's ring file is gone
        let t = partition(prev: prev, restored: restored, disk: disk)
        #expect(t.recovered.isEmpty)
        #expect(t.topologyLost == ["A"])
        #expect(t.staleOrphans.isEmpty)
    }

    @Test func partitionsAreDisjoint() {
        // Documented invariant on `Triage`: "All three sets are disjoint."
        let prev: Set<String> = ["A", "B", "D"]
        let restored: Set<String> = ["A", "E"]
        let disk: Set<String> = ["A", "B", "C", "D"]
        let t = partition(prev: prev, restored: restored, disk: disk)
        #expect(t.recovered.intersection(t.topologyLost).isEmpty)
        #expect(t.recovered.intersection(t.staleOrphans).isEmpty)
        #expect(t.topologyLost.intersection(t.staleOrphans).isEmpty)
    }

    @Test func uuidsAreCaseSensitive() {
        // UUID strings differing only in case are treated as distinct members
        // of the set — `Set<String>` uses String's case-significant equality.
        // A lowercase UUID in `prev` and an uppercase one on disk do not match.
        let prev: Set<String> = ["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"]
        let restored: Set<String> = []
        let disk: Set<String> = ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"]
        let t = partition(prev: prev, restored: restored, disk: disk)
        #expect(t.recovered.isEmpty)
        // prev's lowercase UUID is NOT in disk → no topology-loss either.
        #expect(t.topologyLost.isEmpty)
        // disk's uppercase UUID is NOT in prev → counted as stale orphan.
        #expect(t.staleOrphans == ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])
    }

    @Test func restoredUUIDsOutsidePrevAreIgnored() {
        // A UUID that was restored but never in prev (e.g. a fresh surface
        // spun up before manifest refresh) doesn't appear in any bucket —
        // recovered requires prev membership.
        let prev: Set<String> = ["A"]
        let restored: Set<String> = ["A", "Z"]
        let disk: Set<String> = ["A"]
        let t = partition(prev: prev, restored: restored, disk: disk)
        #expect(t.recovered == ["A"])
        #expect(t.topologyLost.isEmpty)
        #expect(t.staleOrphans.isEmpty)
        // Z is absent from all three partitions — by design.
        #expect(!t.recovered.contains("Z"))
        #expect(!t.topologyLost.contains("Z"))
        #expect(!t.staleOrphans.contains("Z"))
    }
}
