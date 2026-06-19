// Unit tests for adaptive bisection recovery (AlaskaRouter-d0wt).
//
// Pure / deterministic — no SwiftData, no MainActor, no network. The snap
// step is injected as a closure so we can model "this waypoint is off-road
// and has no path" precisely and assert that recovery isolates exactly the
// poisoned legs while salvaging every routable one.

import XCTest
import CoreLocation
@testable import AlaskaRouter

final class SegmentRecoveryTests: XCTestCase {

    private func coord(_ lon: Double) -> CLLocationCoordinate2D {
        // We identify waypoints by longitude (latitude fixed at 0) so a
        // "poison" stop is just a longitude value the fake snap rejects.
        .init(latitude: 0, longitude: lon)
    }

    private func run(firstPairIndex: Int, lons: [Double]) -> MissingRun {
        MissingRun(firstPairIndex: firstPairIndex, waypoints: lons.map(coord))
    }

    /// A fake snap: any sub-run whose waypoints include one of `poison`
    /// longitudes returns `.noRoute`; everything else routes cleanly.
    private func snap(poison: Set<Double>) -> @Sendable (MissingRun) async -> SegmentRecovery.SnapOutcome {
        { sub in
            let hitsPoison = sub.waypoints.contains { poison.contains($0.longitude) }
            return hitsPoison
                ? .noRoute
                : .ok(RoutingResult(coordinates: sub.waypoints, distanceMeters: 0, durationSeconds: 0, legs: []))
        }
    }

    /// Sequential call counter for the `@Sendable` snap closures. Recovery
    /// awaits each snap one at a time (never concurrently), so a plain box
    /// is race-free here — hence `@unchecked Sendable`.
    private final class CallCounter: @unchecked Sendable {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    // MARK: - split

    func testSplitHalvesRunSharingBoundaryWaypoint() {
        // 10 waypoints = 9 pairs. mid = 9/2 = 4 → left 5 wps (4 pairs),
        // right 6 wps (5 pairs), sharing waypoint at lon 4.
        let r = run(firstPairIndex: 0, lons: Array(0 ..< 10).map(Double.init))
        let (left, right) = try! XCTUnwrap(SegmentRecovery.split(r))
        XCTAssertEqual(left.pairCount, 4)
        XCTAssertEqual(right.pairCount, 5)
        XCTAssertEqual(left.firstPairIndex, 0)
        XCTAssertEqual(right.firstPairIndex, 4)
        // Shared boundary: last of left == first of right.
        XCTAssertEqual(left.waypoints.last?.longitude, right.waypoints.first?.longitude)
        XCTAssertEqual(left.waypoints.last?.longitude, 4)
        // Pair coverage is exact: no gap, no overlap.
        XCTAssertEqual(left.pairCount + right.pairCount, r.pairCount)
    }

    func testSplitReturnsNilForSinglePair() {
        XCTAssertNil(SegmentRecovery.split(run(firstPairIndex: 7, lons: [0, 1])))
    }

    func testSplitPreservesFirstPairIndexOffset() {
        // A run that starts partway through a trip must keep its absolute
        // pair indices after splitting.
        let r = run(firstPairIndex: 9, lons: Array(0 ..< 10).map(Double.init))
        let (left, right) = try! XCTUnwrap(SegmentRecovery.split(r))
        XCTAssertEqual(left.firstPairIndex, 9)
        XCTAssertEqual(right.firstPairIndex, 13)   // 9 + mid(4)
    }

    // MARK: - recover

    func testRecoverAllRoutableReturnsSingleSnappedCoveringEveryPair() async {
        let r = run(firstPairIndex: 0, lons: Array(0 ..< 10).map(Double.init))
        let resolved = await SegmentRecovery.recover(r, snap: snap(poison: []))
        XCTAssertEqual(resolved.count, 1)
        guard case let .snapped(sub, _) = resolved[0] else {
            return XCTFail("expected a single snapped sub-run")
        }
        XCTAssertEqual(sub.pairCount, r.pairCount)
    }

    func testRecoverIsolatesSinglePoisonWaypointToItsTwoLegs() async {
        // The Denali scenario: one off-road stop (lon 3) poisons a 9-pair
        // run. The legs touching it are pair 2 (lon 2→3) and pair 3
        // (lon 3→4). Everything else must snap.
        let r = run(firstPairIndex: 0, lons: Array(0 ..< 10).map(Double.init))
        let resolved = await SegmentRecovery.recover(r, snap: snap(poison: [3]))

        let unroutablePairs = unroutableFirstPairIndices(resolved)
        XCTAssertEqual(unroutablePairs, [2, 3], "only the legs touching the off-road stop stay pending")

        // Every other pair is covered by some snapped sub-run, and the
        // snapped + unroutable coverage equals the whole run.
        let snappedPairs = snappedPairCount(resolved)
        XCTAssertEqual(snappedPairs + unroutablePairs.count, r.pairCount)
        XCTAssertTrue(resolved.allSatisfy { if case .pending = $0 { return false } else { return true } },
                      "no transient failures in this scenario")
    }

    func testRecoverIsolatesTwoSeparatePoisonWaypoints() async {
        // Two off-road stops (lon 2 and lon 6). Legs touching them:
        // 1,2 (around lon 2) and 5,6 (around lon 6).
        let r = run(firstPairIndex: 0, lons: Array(0 ..< 10).map(Double.init))
        let resolved = await SegmentRecovery.recover(r, snap: snap(poison: [2, 6]))
        XCTAssertEqual(unroutableFirstPairIndices(resolved), [1, 2, 5, 6])
        XCTAssertEqual(snappedPairCount(resolved) + 4, r.pairCount)
    }

    func testRecoverSinglePairNoRouteStaysUnroutable() async {
        let r = run(firstPairIndex: 4, lons: [0, 1])
        let resolved = await SegmentRecovery.recover(r, snap: snap(poison: [1]))
        XCTAssertEqual(resolved.count, 1)
        guard case let .unroutable(sub) = resolved[0] else {
            return XCTFail("expected unroutable")
        }
        XCTAssertEqual(sub.firstPairIndex, 4)
    }

    func testRecoverTransientLeavesWholeRunPendingWithoutBisecting() async {
        // A transient failure must NOT be mistaken for an unroutable leg.
        let snapCalls = CallCounter()
        let resolved = await SegmentRecovery.recover(
            run(firstPairIndex: 0, lons: Array(0 ..< 10).map(Double.init))
        ) { _ in
            snapCalls.bump()
            return .transient
        }
        XCTAssertEqual(snapCalls.count, 1, "transient stops recursion immediately — no bisection")
        XCTAssertEqual(resolved.count, 1)
        guard case .pending = resolved[0] else {
            return XCTFail("expected pending")
        }
    }

    func testRecoverUsesFewerRequestsThanPerPairFallback() async {
        // Sanity check on the bisection's payoff vs. the per-pair
        // alternative (which would be exactly pairCount = 9 requests).
        let snapCalls = CallCounter()
        _ = await SegmentRecovery.recover(
            run(firstPairIndex: 0, lons: Array(0 ..< 10).map(Double.init))
        ) { sub in
            snapCalls.bump()
            let hits = sub.waypoints.contains { $0.longitude == 3 }
            return hits ? .noRoute : .ok(RoutingResult(coordinates: sub.waypoints, distanceMeters: 0, durationSeconds: 0, legs: []))
        }
        XCTAssertLessThanOrEqual(snapCalls.count, 9, "bisection should not exceed the per-pair request count")
    }

    // MARK: - helpers

    private func unroutableFirstPairIndices(_ resolved: [SegmentRecovery.Resolved]) -> [Int] {
        resolved.compactMap {
            if case let .unroutable(sub) = $0 { return sub.firstPairIndex } else { return nil }
        }
        .sorted()
    }

    private func snappedPairCount(_ resolved: [SegmentRecovery.Resolved]) -> Int {
        resolved.reduce(0) {
            if case let .snapped(sub, _) = $1 { return $0 + sub.pairCount } else { return $0 }
        }
    }
}
