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

    func testBlocksThreeBlocksHaveDistinctLeadingSeparators() {
        // AlaskaRouter-tiiz. With 2 separators (3 blocks) the old code assigned
        // each block the separator at its END, so the last separator was
        // duplicated across two blocks → "ID occurs multiple times" warning and
        // the wrong leadingSeparator. Each block's leading separator must be the
        // one that BEGINS it, and all list IDs must be unique.
        let trip = TestFactories.trip(
            stops: [(0, 0, "A"), (0, 1, "B"), (0, 2, "C"), (0, 3, "D")],
            separatorAfterOrders: [0, 1]
        )

        let blocks = trip.blocks

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.map { $0.waypoints.map(\.label) }, [["A"], ["B"], ["C", "D"]])
        XCTAssertNil(blocks[0].leadingSeparator)
        XCTAssertNotNil(blocks[1].leadingSeparator)
        XCTAssertNotNil(blocks[2].leadingSeparator)
        XCTAssertNotEqual(blocks[1].leadingSeparator?.id, blocks[2].leadingSeparator?.id)
        XCTAssertEqual(Set(trip.listItems.map(\.id)).count, trip.listItems.count)
    }

    func testBlocksToleratesDuplicateAnchorSeparators() {
        // AlaskaRouter-tiiz. A bad reorder used to anchor two separators to the
        // SAME stop, which made `Trip.blocks` slice an inverted range and crash
        // ("Range requires lowerBound <= upperBound"). The derived getter must
        // be total: two separators on one stop describe a single boundary.
        let trip = TestFactories.trip(
            stops: [(0, 0, "A"), (0, 1, "B"), (0, 2, "C")],
            separatorAfterOrders: [0]
        )
        let anchorID = trip.orderedWaypoints[0].id
        let duplicate = BlockSeparator(afterWaypointID: anchorID)
        duplicate.trip = trip
        trip.separators.append(duplicate)

        let blocks = trip.blocks   // must not crash

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map { $0.waypoints.map(\.label) }, [["A"], ["B", "C"]])
        XCTAssertEqual(Set(trip.listItems.map(\.id)).count, trip.listItems.count)
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

    func testRouteRibbonsDoubleMidLegRetrace() {
        // Tier B (AlaskaRouter-pbmw). A→B→C where the snapped routing to C
        // drives back through PART of A→B. The overlap begins mid-leg, so a
        // whole-leg signature can't see it; sub-leg coverage must split leg
        // A→B into a centered head (the un-retraced stub) and a doubled tail.
        //
        // Geometry: A=(0,0) → B=(0,2) forward, then back to C=(0,0.5).
        // The lon 0.5…2 stretch is driven twice; lon 0…0.5 once.
        let snapped = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.5),
            CLLocationCoordinate2D(latitude: 0, longitude: 1.0),
            CLLocationCoordinate2D(latitude: 0, longitude: 1.5),
            CLLocationCoordinate2D(latitude: 0, longitude: 2.0),
            CLLocationCoordinate2D(latitude: 0, longitude: 1.5),
            CLLocationCoordinate2D(latitude: 0, longitude: 1.0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.5),
        ]
        let trip = TestFactories.trip(stops: [
            (0, 0.0, "A"),
            (0, 2.0, "B"),
            (0, 0.5, "C"),
        ])

        let ribbons = trip.routeRibbons(snappedCoords: snapped)

        XCTAssertEqual(ribbons.count, 3)
        // Head of A→B (lon 0…0.5): driven once → centered.
        XCTAssertEqual(ribbons[0].offsetMultiplier, 0)
        // Tail of A→B (lon 0.5…2): doubled → offset.
        XCTAssertEqual(ribbons[1].offsetMultiplier, -0.5)
        // Return B→C over the same tail: doubled, opposite travel side.
        XCTAssertEqual(ribbons[2].offsetMultiplier, -0.5)
        XCTAssertTrue(ribbons.allSatisfy { !$0.isStraightLineFallback })
    }

    // MARK: - Road-stretch lengths (AlaskaRouter-ssl1)

    func testLegDistancesStraightLineFallback() {
        let trip = TestFactories.trip(stops: [(0, 0, "A"), (0, 1, "B"), (0, 2, "C")])
        let legs = trip.legDistancesMeters(snappedCoords: nil)
        XCTAssertEqual(legs.count, 2)
        XCTAssertEqual(legs[0], legs[1], accuracy: 1.0)        // equal 1° lon hops
        XCTAssertEqual(legs[0], 111_320, accuracy: 2_000)      // ~111 km per degree
        XCTAssertEqual(trip.totalDistanceMeters(snappedCoords: nil),
                       legs[0] + legs[1], accuracy: 1.0)
    }

    func testLegDistancesFollowSnappedPolyline() {
        let trip = TestFactories.trip(stops: [(0, 0, "A"), (0, 1, "B")])
        let snap = [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0.5, longitude: 0.5),   // northward detour
            CLLocationCoordinate2D(latitude: 0, longitude: 1),
        ]
        let road = trip.legDistancesMeters(snappedCoords: snap)
        let straight = trip.legDistancesMeters(snappedCoords: nil)
        XCTAssertEqual(road.count, 1)
        XCTAssertGreaterThan(road[0], straight[0])   // the detour is longer than the straight line
    }

    func testDistanceFormatUnits() {
        XCTAssertEqual(DistanceFormat.string(meters: 23_000, useMiles: false), "23 km")
        XCTAssertEqual(DistanceFormat.string(meters: 23_000, useMiles: true), "14 mi")
        XCTAssertEqual(DistanceFormat.string(meters: 400, useMiles: false), "0.4 km") // sub-10 keeps a decimal
    }
}
