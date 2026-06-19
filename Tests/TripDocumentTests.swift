// AlaskaRouter-h113 — lossless trip export/import.
//
// Covers the design invariants: Tier 1 round-trips exactly, Tier 3 (blocks /
// ribbons) re-derives rather than being stored, the Tier 2 routing cache is
// restored when current-engine and dropped when stale, IDs remap correctly in
// copy mode and are preserved (with replace) in preserveID mode, and the
// schemaVersion gate rejects files from a newer app.

import CoreLocation
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import AlaskaRouter

final class TripDocumentTests: XCTestCase {

    /// Mirror of RootView.tripGeometryKey so cache-key assertions match the app.
    private func geometryKey(_ trip: Trip) -> String {
        trip.orderedWaypoints
            .map { String(format: "%.5f,%.5f", $0.lat, $0.lon) }
            .joined(separator: "|")
    }

    @MainActor
    private func insertedTrip(
        in context: ModelContext,
        name: String = "Denali Loop",
        color: TripColor = .teal,
        notes: String = "bring bear spray",
        stops: [(Double, Double, String)],
        separatorAfterOrders: [Int] = []
    ) -> Trip {
        let trip = TestFactories.trip(
            name: name, color: color,
            stops: stops.map { (latitude: $0.0, longitude: $0.1, label: $0.2) },
            separatorAfterOrders: separatorAfterOrders
        )
        trip.notes = notes
        context.insert(trip)
        for wp in trip.waypoints { context.insert(wp) }
        for sep in trip.separators { context.insert(sep) }
        try? context.save()
        return trip
    }

    // MARK: - Tier 1 round-trip

    @MainActor
    func testTier1RoundTripPreservesTripAndWaypointsAndSeparators() throws {
        let context = try TestFactories.inMemoryContext()
        let original = insertedTrip(in: context, stops: [
            (63.0, -149.0, "A"), (63.5, -149.5, "B"), (64.0, -150.0, "C"),
        ], separatorAfterOrders: [1])

        let doc = TripDocument.export(original, context: context)
        let data = try doc.jsonData()
        let restored = try TripDocument.decode(from: data)

        // Import into a fresh store to prove independence from the source.
        let dest = try TestFactories.inMemoryContext()
        let imported = restored.importTrip(into: dest, mode: .copy)

        XCTAssertEqual(imported.name, "Denali Loop")
        XCTAssertEqual(imported.color, .teal)
        XCTAssertEqual(imported.notes, "bring bear spray")
        XCTAssertEqual(imported.orderedWaypoints.map(\.label), ["A", "B", "C"])
        XCTAssertEqual(imported.orderedWaypoints.map(\.order), [0, 1, 2])
        XCTAssertEqual(
            imported.orderedWaypoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                .map { [$0.latitude, $0.longitude] },
            [[63.0, -149.0], [63.5, -149.5], [64.0, -150.0]]
        )
        // createdAt survives (iso8601 is second-precision).
        XCTAssertEqual(imported.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970, accuracy: 1.0)
        // One separator, anchored after order-1 ("B").
        XCTAssertEqual(imported.separators.count, 1)
    }

    // MARK: - Tier 3 re-derives (blocks / ribbons), never stored

    @MainActor
    func testTier3BlocksAndRibbonsRecomputeFromImportedTopology() throws {
        let context = try TestFactories.inMemoryContext()
        let original = insertedTrip(in: context, stops: [
            (0, 0, "A"), (0, 1, "B"), (0, 2, "C"), (0, 3, "D"),
        ], separatorAfterOrders: [1])  // split A,B | C,D  → 2 blocks

        let doc = TripDocument.export(original, context: context)
        // The wire format must not carry derived state.
        let json = String(data: try doc.jsonData(), encoding: .utf8)!
        XCTAssertFalse(json.contains("offsetMultiplier"))
        XCTAssertFalse(json.contains("ribbon"))
        XCTAssertFalse(json.lowercased().contains("\"blocks\""))

        let dest = try TestFactories.inMemoryContext()
        let imported = doc.importTrip(into: dest, mode: .copy)

        // Blocks re-derive to the same shape as the original.
        XCTAssertEqual(imported.blocks.count, 2)
        XCTAssertEqual(imported.blocks.map { $0.waypoints.count }, [2, 2])
        XCTAssertEqual(imported.blocks.map(\.color), original.blocks.map(\.color))
        // Ribbons re-derive (straight-line fallback, no snap supplied).
        let ribbons = imported.routeRibbons(snappedCoords: nil)
        XCTAssertEqual(ribbons.count, 2)
        XCTAssertTrue(ribbons.allSatisfy(\.isStraightLineFallback))
    }

    // MARK: - Tier 2 routing cache

    @MainActor
    func testRoutingCacheRestoredWhenCurrentEngine() throws {
        let context = try TestFactories.inMemoryContext()
        let trip = insertedTrip(in: context, stops: [(0, 0, "A"), (0, 1, "B")])

        // Seed a current-engine per-pair segment + whole-trip blob.
        let snap = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                    CLLocationCoordinate2D(latitude: 0, longitude: 0.5),
                    CLLocationCoordinate2D(latitude: 0, longitude: 1)]
        SegmentCache(context).store(
            from: .init(latitude: 0, longitude: 0), to: .init(latitude: 0, longitude: 1),
            polyline: snap, distanceMeters: 111_000, durationSeconds: 3600)
        trip.setSnappedCoords(snap, geometryKey: geometryKey(trip))
        try? context.save()

        let doc = TripDocument.export(trip, context: context)
        XCTAssertNotNil(doc.routingCache)
        XCTAssertEqual(doc.routingCache?.segments.count, 1)
        XCTAssertNotNil(doc.routingCache?.wholeTrip)

        // Import into a clean store and prove the geometry is usable offline.
        let dest = try TestFactories.inMemoryContext()
        let imported = doc.importTrip(into: dest, mode: .copy)

        // Whole-trip blob valid for the imported coords' key → real geometry.
        let cached = imported.cachedSnappedCoords(for: geometryKey(imported))
        XCTAssertEqual(cached?.count, 3)
        // Per-pair segment landed in the destination's segment cache.
        let seg = SegmentCache(dest).lookupFresh(
            from: .init(latitude: 0, longitude: 0), to: .init(latitude: 0, longitude: 1))
        XCTAssertNotNil(seg)
        XCTAssertEqual(seg?.distanceMeters, 111_000)
    }

    @MainActor
    func testStaleEngineRoutingCacheDroppedOnImport() throws {
        // Hand-build a doc whose cache claims a future router version.
        let doc = TripDocument(
            schemaVersion: TripDocument.currentSchemaVersion,
            appVersion: nil,
            exportedAt: .now,
            trip: TripDTO(id: UUID(), name: "X", colorRaw: TripColor.amber.rawValue,
                          createdAt: .now, notes: ""),
            waypoints: [
                WaypointDTO(id: UUID(), order: 0, lat: 0, lon: 0, label: "A",
                            category: nil, modeRaw: TravelMode.road.rawValue),
                WaypointDTO(id: UUID(), order: 1, lat: 0, lon: 1, label: "B",
                            category: nil, modeRaw: TravelMode.road.rawValue),
            ],
            separators: [],
            routingCache: RoutingCacheDTO(
                routerVersion: RoutingEngineVersion.current + 1,
                wholeTrip: WholeTripSnapDTO(
                    polylineEncoded: PolylineCodec.encode([
                        .init(latitude: 0, longitude: 0), .init(latitude: 0, longitude: 1),
                    ])!,
                    geometryKey: "0.00000,0.00000|0.00000,1.00000",
                    computedAt: .now),
                segments: [])
        )

        let dest = try TestFactories.inMemoryContext()
        let imported = doc.importTrip(into: dest, mode: .copy)

        // Stale-engine cache must be dropped: no usable snapped geometry.
        XCTAssertNil(imported.cachedSnappedCoords(for: geometryKey(imported)))
        XCTAssertNil(imported.snappedRouteEncoded)
    }

    // MARK: - ID strategy

    @MainActor
    func testCopyModeAssignsFreshIDsAndRemapsSeparatorAnchors() throws {
        let context = try TestFactories.inMemoryContext()
        let original = insertedTrip(in: context, stops: [
            (0, 0, "A"), (0, 1, "B"), (0, 2, "C"),
        ], separatorAfterOrders: [1])

        let doc = TripDocument.export(original, context: context)
        let imported = doc.importTrip(into: context, mode: .copy)

        XCTAssertNotEqual(imported.id, original.id)
        let originalWaypointIDs = Set(original.orderedWaypoints.map(\.id))
        XCTAssertTrue(imported.orderedWaypoints.allSatisfy { !originalWaypointIDs.contains($0.id) })

        // The separator's anchor must point at the IMPORTED B, not the original.
        let importedAnchor = imported.separators.first?.afterWaypointID
        XCTAssertNotNil(importedAnchor)
        let importedB = imported.orderedWaypoints.first { $0.label == "B" }
        XCTAssertEqual(importedAnchor, importedB?.id)
        // And the block split still lands in the same place.
        XCTAssertEqual(imported.blocks.map { $0.waypoints.count }, [2, 1])
    }

    @MainActor
    func testPreserveIDModeKeepsIDsAndReplacesExisting() throws {
        let context = try TestFactories.inMemoryContext()
        let original = insertedTrip(in: context, name: "Keep Me", stops: [
            (0, 0, "A"), (0, 1, "B"),
        ])
        let originalID = original.id
        let doc = TripDocument.export(original, context: context)

        // Re-import preserving id into the SAME store → replace, not duplicate.
        let imported = doc.importTrip(into: context, mode: .preserveID)
        XCTAssertEqual(imported.id, originalID)

        let all = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(all.filter { $0.id == originalID }.count, 1, "preserveID must replace, not duplicate")
    }

    // MARK: - On-disk round-trip through TripFileImport (the real URL path)

    @MainActor
    func testFileRoundTripThroughTripFileImport() throws {
        let context = try TestFactories.inMemoryContext()
        let original = insertedTrip(in: context, name: "Parks Hwy", stops: [
            (63.3956, -148.9075, "Cantwell"),
            (63.7298, -148.9128, "Denali Park Entrance"),
            (63.8625, -148.9706, "Healy"),
        ], separatorAfterOrders: [1])

        // Seed a current-engine whole-trip blob so we can prove the routed
        // geometry survives the file → disk → file path and is usable offline.
        let snap = original.orderedWaypoints.map(\.coordinate)
        original.setSnappedCoords(snap, geometryKey: geometryKey(original))
        try? context.save()

        // Write a real .akrtrip file to a temp URL.
        let doc = TripDocument.export(original, context: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roundtrip-\(UUID().uuidString)")
            .appendingPathExtension(UTType.alaskaRouterTripExtension)
        try doc.jsonData().write(to: url, options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        // Read it back through the exact code path .fileImporter / .onOpenURL use.
        let dest = try TestFactories.inMemoryContext()
        let imported = try TripFileImport.importFile(at: url, into: dest, mode: .copy)

        XCTAssertEqual(imported.name, "Parks Hwy")
        XCTAssertEqual(imported.orderedWaypoints.map(\.label),
                       ["Cantwell", "Denali Park Entrance", "Healy"])
        XCTAssertEqual(imported.blocks.count, 2)
        // Routed geometry is valid offline against the imported coords' key.
        XCTAssertNotNil(imported.cachedSnappedCoords(for: geometryKey(imported)))
    }

    @MainActor
    func testImportFileRejectsGarbageData() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("garbage-\(UUID().uuidString)")
            .appendingPathExtension(UTType.alaskaRouterTripExtension)
        try Data("not json at all".utf8).write(to: url, options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let dest = try TestFactories.inMemoryContext()
        XCTAssertThrowsError(try TripFileImport.importFile(at: url, into: dest))
        // And nothing was inserted.
        XCTAssertEqual(try dest.fetchCount(FetchDescriptor<Trip>()), 0)
    }

    // MARK: - Unroutable marker round-trip (2i03)

    @MainActor
    func testUnroutableMarkerRoundTripsThroughExportImport() throws {
        let context = try TestFactories.inMemoryContext()
        let trip = insertedTrip(in: context, stops: [(0, 0, "A"), (0, 1, "B"), (0, 2, "C")])
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 1)
        let c = CLLocationCoordinate2D(latitude: 0, longitude: 2)
        let cache = SegmentCache(context)
        cache.store(from: a, to: b, polyline: [a, b], distanceMeters: 111_000, durationSeconds: 3600)
        cache.storeUnroutable(from: b, to: c)         // terminal no-route leg
        try? context.save()

        let doc = TripDocument.export(trip, context: context)
        XCTAssertEqual(doc.routingCache?.segments.count, 2)
        XCTAssertEqual(doc.routingCache?.segments.filter { $0.isUnroutable == true }.count, 1,
                       "the unroutable leg must be exported with its verdict")

        // Round-trip through bytes so we exercise real JSON coding too.
        let data = try doc.jsonData()
        let restored = try TripDocument.decode(from: data)
        let dest = try TestFactories.inMemoryContext()
        _ = restored.importTrip(into: dest, mode: .copy)

        let destCache = SegmentCache(dest)
        XCTAssertEqual(destCache.lookupFresh(from: a, to: b)?.isUnroutable, false)
        let marker = try XCTUnwrap(destCache.lookupFresh(from: b, to: c))
        XCTAssertTrue(marker.isUnroutable, "imported trip inherits the no-route verdict, so it won't re-probe")
    }

    func testSegmentDTODecodesWithoutUnroutableField() throws {
        // A file written before 2i03 has no `isUnroutable` key. It must still
        // decode (schemaVersion stays 1) and read as routable (nil).
        let json = #"""
        {"fromLat":0,"fromLon":0,"toLat":0,"toLon":1,"polylineEncoded":"[[0,0],[0,1]]","distanceMeters":1,"durationSeconds":1,"computedAt":"2026-06-14T00:00:00Z"}
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(SegmentDTO.self, from: json)
        XCTAssertNil(dto.isUnroutable)
    }

    // MARK: - Schema gate

    func testDecodeRejectsNewerSchemaVersion() throws {
        let json = """
        {
          "schemaVersion": \(TripDocument.currentSchemaVersion + 1),
          "exportedAt": "2026-06-14T00:00:00Z",
          "trip": {"id":"\(UUID().uuidString)","name":"X","colorRaw":"amber","createdAt":"2026-06-14T00:00:00Z","notes":""},
          "waypoints": [],
          "separators": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try TripDocument.decode(from: json)) { error in
            guard case TripDocumentError.unsupportedSchemaVersion = error else {
                return XCTFail("expected unsupportedSchemaVersion, got \(error)")
            }
        }
    }
}
