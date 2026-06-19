// Unit tests for ValhallaProvider (AlaskaRouter-y3g3).
//
// These tests verify the OUTBOUND request shape — body JSON, the
// `use_ferry` knob, request limits — without hitting the network. The
// integration "does Valhalla actually return the AMHS ferry" question
// was answered by the live probe documented in the bean body; we don't
// repeat it here because XCTest shouldn't depend on a public service.

import XCTest
import CoreLocation
@testable import AlaskaRouter

final class ValhallaProviderTests: XCTestCase {

    private func coord(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        .init(latitude: lat, longitude: lon)
    }

    private func decodedBody(of provider: ValhallaProvider,
                             waypoints: [CLLocationCoordinate2D]) throws -> [String: Any] {
        let data = try provider.requestBodyData(for: waypoints)
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any])
    }

    func testRequestBodyHasFerryPreferenceMaxed() throws {
        let provider = ValhallaProvider()
        let json = try decodedBody(
            of: provider,
            waypoints: [coord(61.13083, -146.34833), coord(60.77361, -148.68333)]
        )
        let costingOptions = try XCTUnwrap(json["costing_options"] as? [String: Any])
        let auto = try XCTUnwrap(costingOptions["auto"] as? [String: Any])
        let useFerry = try XCTUnwrap(auto["use_ferry"] as? Double)
        XCTAssertEqual(useFerry, 1.0, "default must strongly prefer ferries — AMHS sailings are the whole point")
    }

    func testRequestBodyAsksForOSRMFormatWithGeoJSONShape() throws {
        // We rely on the OSRM-shaped response so the existing leg / geometry
        // decoder maps over cleanly. Changing either of these would break
        // ValhallaOSRMResponse decoding.
        let provider = ValhallaProvider()
        let json = try decodedBody(
            of: provider,
            waypoints: [coord(0, 0), coord(0, 1)]
        )
        XCTAssertEqual(json["format"] as? String, "osrm")
        XCTAssertEqual(json["shape_format"] as? String, "geojson")
    }

    func testRequestBodyEncodesWaypointsAsBreakLocations() throws {
        let provider = ValhallaProvider()
        let json = try decodedBody(
            of: provider,
            waypoints: [coord(61.21806, -149.90028), coord(63.78361, -148.91056)]
        )
        let locations = try XCTUnwrap(json["locations"] as? [[String: Any]])
        XCTAssertEqual(locations.count, 2)
        XCTAssertEqual(locations[0]["lat"] as? Double, 61.21806)
        XCTAssertEqual(locations[0]["lon"] as? Double, -149.90028)
        XCTAssertEqual(locations[0]["type"] as? String, "break")
        XCTAssertEqual(locations[1]["lat"] as? Double, 63.78361)
        XCTAssertEqual(locations[1]["lon"] as? Double, -148.91056)
    }

    func testRequestBodyUsesAutoCostingWithKilometers() throws {
        let provider = ValhallaProvider()
        let json = try decodedBody(of: provider, waypoints: [coord(0, 0), coord(0, 1)])
        XCTAssertEqual(json["costing"] as? String, "auto")
        let directions = try XCTUnwrap(json["directions_options"] as? [String: Any])
        XCTAssertEqual(directions["units"] as? String, "kilometers")
    }

    func testCustomUseFerryFlowsThroughTheRequest() throws {
        // Build a provider with a milder ferry preference and verify it
        // lands in the request body. Useful when we eventually expose
        // ferry preference as a user-tunable setting.
        let provider = ValhallaProvider(useFerry: 0.5)
        let json = try decodedBody(of: provider, waypoints: [coord(0, 0), coord(0, 1)])
        let costingOptions = try XCTUnwrap(json["costing_options"] as? [String: Any])
        let auto = try XCTUnwrap(costingOptions["auto"] as? [String: Any])
        XCTAssertEqual(auto["use_ferry"] as? Double, 0.5)
    }

    // MARK: - No-route error-body classification (AlaskaRouter-d0wt)
    //
    // A 400 from Valhalla can mean "no drivable path" (permanent, must
    // trigger bisection recovery) OR something else (malformed request,
    // exceeded-max-locations) that we'd rather treat as a transport error.
    // isNoRouteErrorBody must distinguish them so an off-road stop doesn't
    // get shoved into the rate-limit backoff loop.

    func testOSRMFormatNoRouteBodyClassifiedAsNoRoute() {
        // THE shape we actually get: format=osrm makes Valhalla mirror
        // OSRM's error envelope. Verified live against the FOSSGIS demo —
        // this is the body that was silently misclassified before d0wt.
        let body = Data(#"{"code":"NoRoute","message":"Impossible route between points"}"#.utf8)
        XCTAssertTrue(ValhallaProvider.isNoRouteErrorBody(body))
    }

    func testOSRMFormatNoSegmentBodyClassifiedAsNoRoute() {
        // NoSegment = a coordinate couldn't be snapped to any road — the
        // canonical off-road-waypoint case (e.g. centre of Denali Park).
        let body = Data(#"{"code":"NoSegment","message":"One of the supplied input coordinates could not snap to street segment."}"#.utf8)
        XCTAssertTrue(ValhallaProvider.isNoRouteErrorBody(body))
    }

    func testNativeValhallaNoPathBodyClassifiedAsNoRoute() {
        // Fallback shape, kept in case a non-osrm path ever surfaces it.
        let body = Data(#"{"error_code":442,"error":"No path could be found for input"}"#.utf8)
        XCTAssertTrue(ValhallaProvider.isNoRouteErrorBody(body))
    }

    func testOSRMInvalidOptionsNotClassifiedAsNoRoute() {
        // A request-shape error (not a no-route) must NOT trigger bisection.
        let body = Data(#"{"code":"InvalidOptions","message":"Options are invalid."}"#.utf8)
        XCTAssertFalse(ValhallaProvider.isNoRouteErrorBody(body))
    }

    func testNoPathByMessageAloneClassifiedAsNoRoute() {
        // Belt-and-suspenders: even if the error_code drifts, the message
        // text still pins it as a no-route.
        let body = Data(#"{"error":"No path could be found for input"}"#.utf8)
        XCTAssertTrue(ValhallaProvider.isNoRouteErrorBody(body))
    }

    func testExceededMaxLocationsNotClassifiedAsNoRoute() {
        // A different 400 — must NOT be swallowed as no-route, or we'd
        // bisect a request that failed for an unrelated reason.
        let body = Data(#"{"error_code":154,"error":"Exceeded max locations:20"}"#.utf8)
        XCTAssertFalse(ValhallaProvider.isNoRouteErrorBody(body))
    }

    func testGarbageBodyNotClassifiedAsNoRoute() {
        XCTAssertFalse(ValhallaProvider.isNoRouteErrorBody(Data("not json".utf8)))
        XCTAssertFalse(ValhallaProvider.isNoRouteErrorBody(Data()))
    }
}

@MainActor
final class RoutingEngineVersionCacheBumpTests: XCTestCase {

    private func coord(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        .init(latitude: lat, longitude: lon)
    }

    func testFreshStoreStampsCurrentVersion() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        cache.store(
            from: coord(0, 0), to: coord(0, 1),
            polyline: [coord(0, 0), coord(0, 1)],
            distanceMeters: 1, durationSeconds: 1
        )
        let row = try XCTUnwrap(cache.lookup(from: coord(0, 0), to: coord(0, 1)))
        XCTAssertEqual(row.routerVersion, RoutingEngineVersion.current)
    }

    func testLookupFreshRejectsStaleVersionRow() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        // Simulate an existing row from a previous routing engine by
        // inserting a RouteSegment with routerVersion = 0 directly.
        let stale = RouteSegment(
            key: SegmentCache.key(from: coord(0, 0), to: coord(0, 1)),
            fromLat: 0, fromLon: 0, toLat: 0, toLon: 1,
            polylineEncoded: PolylineCodec.encode([coord(0, 0), coord(0, 1)]) ?? "",
            distanceMeters: 1, durationSeconds: 1,
            computedAt: .now,
            routerVersion: 0
        )
        context.insert(stale)
        // unconditional lookup finds the stale row
        XCTAssertNotNil(cache.lookup(from: coord(0, 0), to: coord(0, 1)))
        // lookupFresh treats it as a miss
        XCTAssertNil(cache.lookupFresh(from: coord(0, 0), to: coord(0, 1)))
    }

    func testStoreBringsStaleRowForwardToCurrentVersion() throws {
        let context = try TestFactories.inMemoryContext()
        let cache = SegmentCache(context)
        let stale = RouteSegment(
            key: SegmentCache.key(from: coord(0, 0), to: coord(0, 1)),
            fromLat: 0, fromLon: 0, toLat: 0, toLon: 1,
            polylineEncoded: PolylineCodec.encode([coord(0, 0), coord(0, 1)]) ?? "",
            distanceMeters: 999, durationSeconds: 99,
            computedAt: .distantPast,
            routerVersion: 0
        )
        context.insert(stale)
        // A fresh store against the same pair upserts in place and
        // re-stamps the version — no duplicate row, no orphan.
        cache.store(
            from: coord(0, 0), to: coord(0, 1),
            polyline: [coord(0, 0), coord(0, 1)],
            distanceMeters: 1, durationSeconds: 1
        )
        let row = try XCTUnwrap(cache.lookup(from: coord(0, 0), to: coord(0, 1)))
        XCTAssertEqual(row.routerVersion, RoutingEngineVersion.current)
        XCTAssertEqual(row.distanceMeters, 1)
        // And it's now visible to the planner via lookupFresh.
        XCTAssertNotNil(cache.lookupFresh(from: coord(0, 0), to: coord(0, 1)))
    }

    func testTripCachedSnappedCoordsRejectsStaleVersion() {
        let trip = TestFactories.trip(stops: [
            (61.13083, -146.34833, "Valdez"),
            (60.77361, -148.68333, "Whittier"),
        ])
        // Hand-set a stale snap (router version 0).
        trip.snappedRouteEncoded = PolylineCodec.encode([
            .init(latitude: 61.13083, longitude: -146.34833),
            .init(latitude: 60.77361, longitude: -148.68333),
        ])
        let key = "61.13083,-146.34833|60.77361,-148.68333"
        trip.snappedRouteKey = key
        trip.snappedRouteRouterVersion = 0
        XCTAssertNil(
            trip.cachedSnappedCoords(for: key),
            "stale-version snap must be treated as a miss so the new engine re-fetches"
        )
        // After a fresh setSnappedCoords, the cache is valid again.
        trip.setSnappedCoords([
            .init(latitude: 61.13083, longitude: -146.34833),
            .init(latitude: 60.77361, longitude: -148.68333),
        ], geometryKey: key)
        XCTAssertNotNil(trip.cachedSnappedCoords(for: key))
    }
}
