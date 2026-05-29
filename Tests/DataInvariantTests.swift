import CoreLocation
import SwiftData
import XCTest
@testable import AlaskaRouter

final class DataInvariantTests: XCTestCase {
    func testSmartInsertPositionAppendsForShortRoutes() {
        let candidate = CLLocationCoordinate2D(latitude: 0, longitude: 5)
        let oneStop = [TestFactories.waypoint(order: 0, latitude: 0, longitude: 0)]

        XCTAssertEqual(SmartInsert.position(forCoordinate: candidate, in: []), 0)
        XCTAssertEqual(SmartInsert.position(forCoordinate: candidate, in: oneStop), 1)
    }

    func testSmartInsertPositionChoosesCheapestMiddleInsertion() {
        let waypoints = [
            TestFactories.waypoint(order: 0, latitude: 0, longitude: 0),
            TestFactories.waypoint(order: 1, latitude: 0, longitude: 10),
        ]
        let candidate = CLLocationCoordinate2D(latitude: 0, longitude: 5)

        XCTAssertEqual(SmartInsert.position(forCoordinate: candidate, in: waypoints), 1)
    }

    @MainActor
    func testInsertSmartRenumbersExistingStops() throws {
        let context = try TestFactories.inMemoryContext()
        let trip = TestFactories.trip(stops: [
            (0, 0, "A"),
            (0, 10, "B"),
        ])
        context.insert(trip)
        try context.save()

        let inserted = SmartInsert.insertSmart(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 5),
            label: "Middle",
            category: "test",
            into: trip,
            using: context
        )

        XCTAssertEqual(inserted.order, 1)
        XCTAssertEqual(trip.orderedWaypoints.map(\.label), ["A", "Middle", "B"])
        XCTAssertEqual(trip.orderedWaypoints.map(\.order), [0, 1, 2])
    }

    func testBlocksIncludeImplicitFirstBlockAndIgnoreDegenerateSeparators() {
        let trip = TestFactories.trip(
            stops: [
                (0, 0, "A"),
                (0, 1, "B"),
                (0, 2, "C"),
            ],
            separatorAfterOrders: [0, 2]
        )
        let missingSeparator = BlockSeparator(afterWaypointID: UUID())
        missingSeparator.trip = trip
        trip.separators.append(missingSeparator)

        let blocks = trip.blocks

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].id, "block-0")
        XCTAssertNil(blocks[0].leadingSeparator)
        XCTAssertEqual(blocks[0].waypoints.map(\.label), ["A"])
        XCTAssertEqual(blocks[1].waypoints.map(\.label), ["B", "C"])
        XCTAssertEqual(trip.listItems.count, 5)
    }

    func testSnapCacheHydratesOnlyForMatchingKey() {
        let trip = Trip(name: "Cache Test")
        let coords = [
            CLLocationCoordinate2D(latitude: 63.0, longitude: -149.0),
            CLLocationCoordinate2D(latitude: 64.0, longitude: -148.0),
        ]

        trip.setSnappedCoords(coords, geometryKey: "a")

        XCTAssertEqual(trip.cachedSnappedCoords(for: "a")?.count, 2)
        XCTAssertNil(trip.cachedSnappedCoords(for: "b"))

        trip.clearSnappedCache()
        XCTAssertNil(trip.cachedSnappedCoords(for: "a"))
    }

    func testSnapCacheRejectsMalformedJSON() {
        let trip = Trip(name: "Cache Test")
        trip.snappedRouteEncoded = "not json"
        trip.snappedRouteKey = "a"

        XCTAssertNil(trip.cachedSnappedCoords(for: "a"))
    }

    func testRouteRibbonsUseStraightFallbackWhenNoSnapExists() {
        let trip = TestFactories.trip(stops: [
            (0, 0, "A"),
            (0, 1, "B"),
        ])

        let ribbons = trip.routeRibbons(snappedCoords: nil)

        XCTAssertEqual(ribbons.count, 1)
        XCTAssertTrue(ribbons[0].isStraightLineFallback)
        XCTAssertEqual(ribbons[0].offsetMultiplier, 0)
        XCTAssertEqual(ribbons[0].coords.count, 2)
    }

    func testRouteRibbonsSplitAtBlockBoundaries() {
        let trip = TestFactories.trip(
            stops: [
                (0, 0, "A"),
                (0, 1, "B"),
                (0, 2, "C"),
            ],
            separatorAfterOrders: [1]
        )

        let ribbons = trip.routeRibbons(snappedCoords: nil)

        XCTAssertEqual(ribbons.count, 2)
        XCTAssertEqual(ribbons.map(\.color), [trip.blocks[0].color, trip.blocks[1].color])
    }

    func testRouteRibbonsDetectOutAndBackPasses() {
        let trip = TestFactories.trip(stops: [
            (0, 0, "A"),
            (0, 1, "B"),
            (0, 0, "A Return"),
        ])

        let ribbons = trip.routeRibbons(snappedCoords: nil)

        XCTAssertEqual(ribbons.count, 2)
        XCTAssertEqual(ribbons.map(\.offsetMultiplier), [-0.5, -0.5])
        XCTAssertTrue(ribbons.allSatisfy(\.isStraightLineFallback))
    }

    func testRouteRibbonsCenterLoneStretchAfterOutAndBack() {
        // AlaskaRouter-pbmw regression. A→B→A→C: the A–B road is driven twice
        // (out-and-back) and must be doubled, but the final A→C stretch is
        // driven once and must stay CENTERED (offset 0). The old algorithm
        // shifted every ribbon once the trip had ≥2 passes anywhere.
        let trip = TestFactories.trip(stops: [
            (0, 0, "A"),
            (0, 1, "B"),
            (0, 0, "A Return"),
            (0, -1, "C"),
        ])

        let ribbons = trip.routeRibbons(snappedCoords: nil)

        XCTAssertEqual(ribbons.count, 3)
        // The doubled A–B road: two ribbons on opposite travel sides.
        XCTAssertEqual(ribbons[0].offsetMultiplier, -0.5)
        XCTAssertEqual(ribbons[1].offsetMultiplier, -0.5)
        // The lone A→C stretch is centered — the bug.
        XCTAssertEqual(ribbons[2].offsetMultiplier, 0)
    }

    func testRouteRibbonsCenterSharpTurnWithoutRetrace() {
        // A sharp turn (direction reversal at B) over roads that do NOT
        // overlap must stay centered. The old algorithm split this into two
        // "passes" and shifted both off-center even though nothing is doubled.
        let trip = TestFactories.trip(stops: [
            (0, 0, "A"),
            (2, 0, "B"),
            (1, 1, "C"),
        ])

        let ribbons = trip.routeRibbons(snappedCoords: nil)

        XCTAssertTrue(ribbons.allSatisfy { $0.offsetMultiplier == 0 })
    }
}
