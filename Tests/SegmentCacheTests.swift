// Unit tests for the per-segment routing cache (AlaskaRouter-un6b).

import XCTest
import CoreLocation
@testable import AlaskaRouter

@MainActor
final class SegmentCacheTests: XCTestCase {

    private func coord(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        .init(latitude: lat, longitude: lon)
    }

    // MARK: - Key shape

    func testKeyIsDirectional() {
        let a = coord(61.21806, -149.90028)
        let b = coord(63.78361, -148.91056)
        let ab = SegmentCache.key(from: a, to: b)
        let ba = SegmentCache.key(from: b, to: a)
        XCTAssertNotEqual(ab, ba, "directed key must distinguish (A→B) from (B→A) for one-way roads")
    }

    func testKeyRoundsToFiveDecimals() {
        let exact = coord(61.21806, -149.90028)
        let jitter = coord(61.218064999, -149.90027999)  // sub-1.1m drift
        XCTAssertEqual(
            SegmentCache.key(from: exact, to: exact),
            SegmentCache.key(from: jitter, to: jitter),
            "5-decimal rounding (~1.1 m) must absorb sub-meter coordinate jitter"
        )
    }

    // MARK: - Lookup / store

    func testLookupMissReturnsNil() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        XCTAssertNil(cache.lookup(from: coord(61, -149), to: coord(63, -148)))
    }

    func testStoreThenLookupReturnsRow() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        let a = coord(61.21806, -149.90028)
        let b = coord(63.78361, -148.91056)
        cache.store(
            from: a, to: b,
            polyline: [a, coord(62, -149.5), b],
            distanceMeters: 462_000,
            durationSeconds: 18_000
        )
        let found = try XCTUnwrap(cache.lookup(from: a, to: b))
        XCTAssertEqual(found.distanceMeters, 462_000)
        XCTAssertEqual(found.durationSeconds, 18_000)
        XCTAssertEqual(found.coordinates.count, 3)
    }

    func testStoreUpdatesExistingRowInsteadOfDuplicating() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        let a = coord(61.21806, -149.90028)
        let b = coord(63.78361, -148.91056)
        cache.store(from: a, to: b, polyline: [a, b], distanceMeters: 100, durationSeconds: 1)
        cache.store(from: a, to: b, polyline: [a, coord(62, -149), b], distanceMeters: 200, durationSeconds: 2)
        let found = try XCTUnwrap(cache.lookup(from: a, to: b))
        XCTAssertEqual(found.distanceMeters, 200, "second store should update, not duplicate")
        XCTAssertEqual(found.coordinates.count, 3)
    }

    // MARK: - Unroutable markers (2i03)

    func testStoreUnroutableMarkerIsLookupableAndFlagged() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        let a = coord(63.34111, -150.73414)   // off-road Denali-centre-ish
        let b = coord(63.39218, -148.95386)
        cache.storeUnroutable(from: a, to: b)
        let found = try XCTUnwrap(cache.lookupFresh(from: a, to: b))
        XCTAssertTrue(found.isUnroutable)
        XCTAssertTrue(found.coordinates.isEmpty, "a no-route marker carries no geometry")
        XCTAssertEqual(found.routerVersion, RoutingEngineVersion.current,
                       "marker is version-stamped so an engine bump re-probes it")
    }

    func testUpsertFlipsUnroutableVerdictBothWays() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        let a = coord(61, -149)
        let b = coord(62, -149)
        // Routable → unroutable (e.g. router data regressed / re-checked).
        cache.store(from: a, to: b, polyline: [a, b], distanceMeters: 10, durationSeconds: 1)
        cache.storeUnroutable(from: a, to: b)
        XCTAssertEqual(try XCTUnwrap(cache.lookup(from: a, to: b)).isUnroutable, true)
        // Unroutable → routable (e.g. a stop nudged onto a road) clears it.
        cache.store(from: a, to: b, polyline: [a, b], distanceMeters: 20, durationSeconds: 2)
        let row = try XCTUnwrap(cache.lookup(from: a, to: b))
        XCTAssertFalse(row.isUnroutable, "a successful snap must clear the no-route flag")
        XCTAssertEqual(row.distanceMeters, 20)
    }

    func testLookupAllPairsReturnsNilOnAnyMiss() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        let a = coord(61, -149)
        let b = coord(62, -149)
        let c = coord(63, -149)
        cache.store(from: a, to: b, polyline: [a, b], distanceMeters: 1, durationSeconds: 1)
        // (b, c) not stored
        XCTAssertNil(cache.lookupAllPairs([a, b, c]))
    }

    func testLookupAllPairsReturnsRowsOnFullHit() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        let a = coord(61, -149)
        let b = coord(62, -149)
        let c = coord(63, -149)
        cache.store(from: a, to: b, polyline: [a, b], distanceMeters: 1, durationSeconds: 1)
        cache.store(from: b, to: c, polyline: [b, c], distanceMeters: 2, durationSeconds: 2)
        let rows = try XCTUnwrap(cache.lookupAllPairs([a, b, c]))
        XCTAssertEqual(rows.count, 2)
    }

    // MARK: - Stitcher

    func testStitcherDedupesSharedEndpoints() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        let a = coord(61, -149)
        let b = coord(62, -149)
        let c = coord(63, -149)
        cache.store(from: a, to: b, polyline: [a, coord(61.5, -149), b], distanceMeters: 1, durationSeconds: 1)
        cache.store(from: b, to: c, polyline: [b, coord(62.5, -149), c], distanceMeters: 2, durationSeconds: 2)
        let rows = try XCTUnwrap(cache.lookupAllPairs([a, b, c]))
        let stitched = SegmentStitcher.stitch(rows)
        // 3 + (3 - 1) = 5 coords; the shared `b` appears exactly once.
        XCTAssertEqual(stitched.count, 5)
        let bs = stitched.filter { abs($0.latitude - 62) < 1e-9 && abs($0.longitude - (-149)) < 1e-9 }
        XCTAssertEqual(bs.count, 1, "shared endpoint must not be duplicated at the join")
    }
}

@MainActor
final class PolylineCodecTests: XCTestCase {
    func testRoundtripPreservesCoordinates() throws {
        let coords = [
            CLLocationCoordinate2D(latitude: 61.21806, longitude: -149.90028),
            CLLocationCoordinate2D(latitude: 62.50000, longitude: -149.50000),
            CLLocationCoordinate2D(latitude: 63.78361, longitude: -148.91056),
        ]
        let encoded = try XCTUnwrap(PolylineCodec.encode(coords))
        let decoded = try XCTUnwrap(PolylineCodec.decode(encoded))
        XCTAssertEqual(decoded.count, coords.count)
        for (a, b) in zip(coords, decoded) {
            XCTAssertEqual(a.latitude, b.latitude, accuracy: 1e-9)
            XCTAssertEqual(a.longitude, b.longitude, accuracy: 1e-9)
        }
    }

    func testDecodeRejectsMalformed() {
        XCTAssertNil(PolylineCodec.decode("not-json"))
        XCTAssertNil(PolylineCodec.decode("{}"))
    }
}

@MainActor
final class MonotonicWaypointIndexesTests: XCTestCase {
    private func coord(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        .init(latitude: lat, longitude: lon)
    }

    func testStraightlineMapping() {
        let poly = [coord(0, 0), coord(0, 1), coord(0, 2), coord(0, 3), coord(0, 4)]
        let stops = [coord(0, 0), coord(0, 2), coord(0, 4)]
        XCTAssertEqual(Trip.monotonicWaypointIndexes(polyline: poly, waypoints: stops), [0, 2, 4])
    }

    func testOutAndBackRetraceMonotonic() {
        // A → B → A produces a forward polyline 0…5 and the same back.
        // Each waypoint should map forward (no rewinding the cursor).
        let poly = [
            coord(0, 0), coord(0, 1), coord(0, 2),       // A→B forward
            coord(0, 1), coord(0, 0),                    // B→A return
        ]
        let stops = [coord(0, 0), coord(0, 2), coord(0, 0)]
        let idx = Trip.monotonicWaypointIndexes(polyline: poly, waypoints: stops)
        XCTAssertEqual(idx[0], 0)
        XCTAssertEqual(idx[1], 2)
        XCTAssertEqual(idx[2], 4)
        // Monotonic: cursor must not rewind.
        XCTAssertEqual(idx, idx.sorted())
    }

    func testEmptyPolylineGivesEmpty() {
        XCTAssertEqual(Trip.monotonicWaypointIndexes(polyline: [], waypoints: [coord(0, 0)]), [])
    }
}
