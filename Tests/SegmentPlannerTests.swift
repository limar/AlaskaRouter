// Unit tests for the partial-fetch planner (AlaskaRouter-2l0i).
//
// Pure functions only — no SwiftData, no MainActor, no network. The
// planner's job is "given a per-pair cache state, decide which runs of
// missing pairs to fetch and how to chunk them so they fit the routing
// provider's per-request location cap."

import XCTest
import CoreLocation
@testable import AlaskaRouter

final class SegmentPlannerTests: XCTestCase {

    private func coord(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        .init(latitude: lat, longitude: lon)
    }

    // MARK: - missingRuns

    func testAllPairsCachedYieldsNoRuns() {
        let stops = [coord(0, 0), coord(0, 1), coord(0, 2)]
        let geometries: [PairGeometry] = [
            .snapped([coord(0, 0), coord(0, 1)]),
            .snapped([coord(0, 1), coord(0, 2)]),
        ]
        XCTAssertTrue(SegmentPlanner.missingRuns(in: geometries, stops: stops).isEmpty)
    }

    func testSinglePendingPairProducesOneRunOfTwoWaypoints() {
        let stops = [coord(0, 0), coord(0, 1), coord(0, 2)]
        let geometries: [PairGeometry] = [
            .snapped([coord(0, 0), coord(0, 1)]),
            .pending,
        ]
        let runs = SegmentPlanner.missingRuns(in: geometries, stops: stops)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].firstPairIndex, 1)
        XCTAssertEqual(runs[0].waypoints.count, 2)
        XCTAssertEqual(runs[0].waypoints[0].longitude, 1)
        XCTAssertEqual(runs[0].waypoints[1].longitude, 2)
    }

    func testTwoAdjacentPendingPairsFormOneRun() {
        let stops = [coord(0, 0), coord(0, 1), coord(0, 2), coord(0, 3)]
        let geometries: [PairGeometry] = [.snapped([coord(0, 0), coord(0, 1)]), .pending, .pending]
        let runs = SegmentPlanner.missingRuns(in: geometries, stops: stops)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].firstPairIndex, 1)
        XCTAssertEqual(runs[0].pairCount, 2)
        XCTAssertEqual(runs[0].waypoints.count, 3)   // 2 pairs ⇒ 3 waypoints
    }

    func testNonAdjacentPendingPairsFormSeparateRuns() {
        let stops = [coord(0, 0), coord(0, 1), coord(0, 2), coord(0, 3), coord(0, 4)]
        let geometries: [PairGeometry] = [
            .pending,
            .snapped([coord(0, 1), coord(0, 2)]),
            .pending,
            .snapped([coord(0, 3), coord(0, 4)]),
        ]
        let runs = SegmentPlanner.missingRuns(in: geometries, stops: stops)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].firstPairIndex, 0)
        XCTAssertEqual(runs[0].pairCount, 1)
        XCTAssertEqual(runs[1].firstPairIndex, 2)
        XCTAssertEqual(runs[1].pairCount, 1)
    }

    func testAllPendingFormsOneRunSpanningTheTrip() {
        let stops = (0 ... 4).map { coord(0, Double($0)) }
        let geometries: [PairGeometry] = Array(repeating: .pending, count: 4)
        let runs = SegmentPlanner.missingRuns(in: geometries, stops: stops)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].firstPairIndex, 0)
        XCTAssertEqual(runs[0].pairCount, 4)
        XCTAssertEqual(runs[0].waypoints.count, 5)
    }

    // MARK: - missingRuns with terminal unroutable pairs (2i03)

    func testUnroutablePairIsNotFetchedAndClosesRuns() {
        // [snapped, unroutable, pending, snapped]: only the pending pair (2)
        // is a missing run. The unroutable pair (1) must never be fetched.
        let stops = (0 ... 4).map { coord(0, Double($0)) }
        let geometries: [PairGeometry] = [
            .snapped([coord(0, 0), coord(0, 1)]),
            .unroutable,
            .pending,
            .snapped([coord(0, 3), coord(0, 4)]),
        ]
        let runs = SegmentPlanner.missingRuns(in: geometries, stops: stops)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].firstPairIndex, 2)
        XCTAssertEqual(runs[0].pairCount, 1)
    }

    func testUnroutablePairSplitsAdjacentPendingIntoSeparateRuns() {
        // [pending, unroutable, pending]: the terminal pair in the middle
        // bounds the run, so the two pending pairs become separate fetches
        // (not one run spanning the dead leg).
        let stops = (0 ... 3).map { coord(0, Double($0)) }
        let geometries: [PairGeometry] = [.pending, .unroutable, .pending]
        let runs = SegmentPlanner.missingRuns(in: geometries, stops: stops)
        XCTAssertEqual(runs.map(\.firstPairIndex), [0, 2])
        XCTAssertTrue(runs.allSatisfy { $0.pairCount == 1 })
    }

    func testAllUnroutableYieldsNoRuns() {
        let stops = (0 ... 3).map { coord(0, Double($0)) }
        let geometries: [PairGeometry] = Array(repeating: .unroutable, count: 3)
        XCTAssertTrue(SegmentPlanner.missingRuns(in: geometries, stops: stops).isEmpty)
    }

    // MARK: - chunk

    func testChunkNoOpWhenRunFitsCap() {
        let run = MissingRun(
            firstPairIndex: 0,
            waypoints: (0 ..< 5).map { coord(0, Double($0)) }
        )
        let chunks = SegmentPlanner.chunk(run, maxLocations: 10)
        XCTAssertEqual(chunks, [run])
    }

    func testChunkSplitsOversizedRunWithSharedBoundaries() {
        // 25 waypoints (= 24 pairs) at cap 10 should split into 10 + 10 + 7
        // sharing boundaries at positions 9 and 18. Pair coverage is exact:
        //   chunk 0 covers pairs 0..8  (9 pairs, waypoints 0..9)
        //   chunk 1 covers pairs 9..17 (9 pairs, waypoints 9..18)
        //   chunk 2 covers pairs 18..23 (6 pairs, waypoints 18..24)
        let run = MissingRun(
            firstPairIndex: 0,
            waypoints: (0 ..< 25).map { coord(0, Double($0)) }
        )
        let chunks = SegmentPlanner.chunk(run, maxLocations: 10)
        XCTAssertEqual(chunks.count, 3)

        XCTAssertEqual(chunks[0].firstPairIndex, 0)
        XCTAssertEqual(chunks[0].waypoints.count, 10)
        XCTAssertEqual(chunks[1].firstPairIndex, 9)
        XCTAssertEqual(chunks[1].waypoints.count, 10)
        XCTAssertEqual(chunks[2].firstPairIndex, 18)
        XCTAssertEqual(chunks[2].waypoints.count, 7)

        // Total pair coverage must equal the input run's pair count.
        let totalPairs = chunks.reduce(0) { $0 + $1.pairCount }
        XCTAssertEqual(totalPairs, run.pairCount)

        // Boundaries are shared waypoints: last of chunk i == first of chunk i+1.
        for i in 0 ..< chunks.count - 1 {
            XCTAssertEqual(chunks[i].waypoints.last?.longitude, chunks[i + 1].waypoints.first?.longitude)
        }

        // Every chunk respects the cap.
        for c in chunks {
            XCTAssertLessThanOrEqual(c.waypoints.count, 10)
        }
    }

    func testChunkRespectsTheProductionCapByDefault() {
        // No explicit `maxLocations:` argument → uses
        // RoutingRequestLimits.maxLocationsPerRoutingRequest. This is the
        // tripwire test: if someone bumps the cap above what FOSSGIS
        // Valhalla accepts (20), the assertion at the provider boundary
        // will fire — but here we just confirm the default is honored.
        let cap = RoutingRequestLimits.maxLocationsPerRoutingRequest
        let run = MissingRun(
            firstPairIndex: 0,
            waypoints: (0 ..< cap * 3).map { coord(0, Double($0)) }
        )
        let chunks = SegmentPlanner.chunk(run)
        for c in chunks {
            XCTAssertLessThanOrEqual(c.waypoints.count, cap)
        }
    }

    func testChunkClampsImpossibleMaxLocations() {
        // maxLocations < 2 makes no sense — the planner clamps to 2 so
        // the test doesn't loop forever. (Anyone setting the constant to
        // <2 is misconfiguring the system.)
        let run = MissingRun(
            firstPairIndex: 0,
            waypoints: (0 ..< 5).map { coord(0, Double($0)) }
        )
        let chunks = SegmentPlanner.chunk(run, maxLocations: 1)
        XCTAssertFalse(chunks.isEmpty)
        for c in chunks { XCTAssertEqual(c.waypoints.count, 2) }
    }

    // MARK: - stitchedPolyline

    func testStitchedPolylineConcatenatesAndDedupesBoundaries() {
        let stops = [coord(0, 0), coord(0, 1), coord(0, 2)]
        let geometries: [PairGeometry] = [
            .snapped([coord(0, 0), coord(0, 0.5), coord(0, 1)]),
            .snapped([coord(0, 1), coord(0, 1.5), coord(0, 2)]),
        ]
        let stitched = SegmentPlanner.stitchedPolyline(geometries: geometries, stops: stops)
        XCTAssertEqual(stitched.count, 5)   // 3 + (3 - 1) = 5; shared boundary deduped
        let shared = stitched.filter { abs($0.longitude - 1.0) < 1e-9 }
        XCTAssertEqual(shared.count, 1, "shared waypoint must appear exactly once")
    }

    func testStitchedPolylineSubstitutesStraightLineForPendingPair() {
        let stops = [coord(0, 0), coord(0, 1), coord(0, 2)]
        let geometries: [PairGeometry] = [
            .snapped([coord(0, 0), coord(0, 0.5), coord(0, 1)]),
            .pending,
        ]
        let stitched = SegmentPlanner.stitchedPolyline(geometries: geometries, stops: stops)
        // 3 from snapped + (2 - 1) from pending straight-line = 4
        XCTAssertEqual(stitched.count, 4)
        XCTAssertEqual(stitched.last?.longitude, 2.0)
    }

    func testStitchedPolylineSubstitutesStraightLineForUnroutablePair() {
        // (2i03) An unroutable leg renders the same straight dashed line as
        // a pending one — no road geometry, just the stop-to-stop segment.
        let stops = [coord(0, 0), coord(0, 1), coord(0, 2)]
        let geometries: [PairGeometry] = [
            .snapped([coord(0, 0), coord(0, 0.5), coord(0, 1)]),
            .unroutable,
        ]
        let stitched = SegmentPlanner.stitchedPolyline(geometries: geometries, stops: stops)
        XCTAssertEqual(stitched.count, 4)              // 3 snapped + (2-1) straight
        XCTAssertEqual(stitched.last?.longitude, 2.0)
    }

    func testStitchedPolylineEmptyForDegenerateInputs() {
        XCTAssertEqual(
            SegmentPlanner.stitchedPolyline(geometries: [], stops: [coord(0, 0)]).count,
            0
        )
    }
}

// MARK: - RoutingRequestLimits

final class RoutingRequestLimitsTests: XCTestCase {
    func testProductionCapStaysWellUnderTheFOSSGISValhallaHardLimit() {
        // FOSSGIS Valhalla returns HTTP 400 "Exceeded max locations: 20"
        // for any /route request with more than 20 locations. Our cap
        // must stay strictly below that — set well under to tolerate a
        // future tightening. See RoutingRequestLimits.swift header.
        XCTAssertLessThan(RoutingRequestLimits.maxLocationsPerRoutingRequest, 20)
        XCTAssertGreaterThanOrEqual(RoutingRequestLimits.maxLocationsPerRoutingRequest, 2)
    }
}
