// Lossless trip export/import document (AlaskaRouter-h113).
//
// Reinstalls during development wipe SwiftData, destroying created trips. This
// is the on-disk `.akrtrip` representation that survives a reinstall, transfers
// a trip between device and simulator, and lets a specific trip be attached to
// a bug report.
//
// Design — the source-of-truth vs. derived split:
//   • Tier 1 (always exported, not recomputable): Trip identity + waypoints +
//     block separators.
//   • Tier 2 (optional cache, not recomputable OFFLINE): routed snap geometry
//     — the whole-trip blob + per-pair RouteSegments. Self-validating on
//     import: kept only when its `routerVersion` matches the running engine,
//     otherwise dropped and re-snapped.
//   • Tier 3 (NEVER exported, always recomputed): blocks, per-block colors,
//     route ribbons / onion offsets, pending-snap status. All are pure
//     derivations of (waypoints + separators + snap) — storing them would only
//     create a staleness risk. See `Trip.blocks` and `Trip.routeRibbons`.
//
// This is a DTO layer deliberately decoupled from the SwiftData `@Model`
// schema: a future SwiftData migration must not break the ability to read an
// older export file. The wire format is versioned by `schemaVersion`.

import Foundation
import SwiftData
import CoreLocation

// MARK: - Wire format (Codable DTOs)

/// Top-level envelope written to a `.akrtrip` file.
struct TripDocument: Codable {
    /// Bumped when the wire format changes incompatibly. The decoder refuses
    /// files newer than `currentSchemaVersion` (we can't know their shape).
    var schemaVersion: Int
    /// Marketing/version string of the exporting app, for diagnostics. Not
    /// used by the importer — purely informational.
    var appVersion: String?
    var exportedAt: Date
    var trip: TripDTO
    var waypoints: [WaypointDTO]
    var separators: [SeparatorDTO]
    /// Tier 2 — present only when current-engine routed geometry was available
    /// at export time.
    var routingCache: RoutingCacheDTO?

    static let currentSchemaVersion = 1
}

struct TripDTO: Codable {
    var id: UUID
    var name: String
    var colorRaw: String
    var createdAt: Date
    var notes: String
}

struct WaypointDTO: Codable {
    var id: UUID
    var order: Int
    var lat: Double
    var lon: Double
    var label: String?
    var category: String?
    var modeRaw: String
}

struct SeparatorDTO: Codable {
    var id: UUID
    /// References a `WaypointDTO.id`. Remapped through the same id-translation
    /// table as the waypoints on import so the anchor still resolves.
    var afterWaypointID: UUID?
}

/// Tier 2 snapshot. Everything here carries one `routerVersion` because we
/// only ever export geometry produced by the *current* engine (stale rows are
/// skipped at export time — the importer would drop them anyway).
struct RoutingCacheDTO: Codable {
    var routerVersion: Int
    var wholeTrip: WholeTripSnapDTO?
    var segments: [SegmentDTO]
}

struct WholeTripSnapDTO: Codable {
    /// `[[lat,lon],…]` JSON, the same format as `Trip.snappedRouteEncoded`.
    var polylineEncoded: String
    /// The `tripGeometryKey` (`lat,lon`@5dp, "|"-joined) this blob was snapped
    /// for. Because exported coordinates are exact, this key recomputes
    /// identically on import — so an imported trip renders real road geometry
    /// instantly, even offline.
    var geometryKey: String
    var computedAt: Date
}

struct SegmentDTO: Codable {
    var fromLat: Double
    var fromLon: Double
    var toLat: Double
    var toLon: Double
    var polylineEncoded: String
    var distanceMeters: Double
    var durationSeconds: Double
    var computedAt: Date
}

// MARK: - Errors

enum TripDocumentError: LocalizedError {
    /// File declares a `schemaVersion` newer than this build understands.
    case unsupportedSchemaVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            return "This trip file (format v\(found)) was made by a newer "
                + "version of AlaskaRouter. This build understands up to "
                + "format v\(supported). Update the app to import it."
        }
    }
}

// MARK: - JSON

extension TripDocument {
    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        // Pretty + stable key order: the file is meant to be human-inspectable
        // and diff-friendly (matches the PolylineCodec rationale).
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Serialize to the on-disk JSON form.
    func jsonData() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    /// Parse a `.akrtrip` file. Throws `unsupportedSchemaVersion` for files
    /// from a newer app, and the underlying `DecodingError` for malformed input.
    static func decode(from data: Data) throws -> TripDocument {
        let doc = try makeDecoder().decode(TripDocument.self, from: data)
        guard doc.schemaVersion <= currentSchemaVersion else {
            throw TripDocumentError.unsupportedSchemaVersion(
                found: doc.schemaVersion, supported: currentSchemaVersion)
        }
        return doc
    }
}

// MARK: - Export (Trip → TripDocument)

extension TripDocument {
    /// Build a document from a live `Trip`.
    ///
    /// When `includeRoutingCache` is true, the Tier 2 snapshot is assembled
    /// from CURRENT-engine geometry only: the per-pair segment cache
    /// (`SegmentCache.lookupFresh`) and the whole-trip blob (kept only if its
    /// `snappedRouteRouterVersion` matches the running engine). A trip with no
    /// current routed geometry exports with `routingCache == nil`.
    @MainActor
    static func export(
        _ trip: Trip,
        context: ModelContext,
        appVersion: String? = nil,
        includeRoutingCache: Bool = true
    ) -> TripDocument {
        let stops = trip.orderedWaypoints

        let tripDTO = TripDTO(
            id: trip.id,
            name: trip.name,
            colorRaw: trip.colorRaw,
            createdAt: trip.createdAt,
            notes: trip.notes
        )

        let waypointDTOs = stops.map { wp in
            WaypointDTO(
                id: wp.id, order: wp.order, lat: wp.lat, lon: wp.lon,
                label: wp.label, category: wp.category, modeRaw: wp.modeRaw
            )
        }

        // Only separators with a still-resolvable anchor are worth exporting;
        // a degenerate one (anchor deleted) would re-derive to nothing anyway.
        let liveWaypointIDs = Set(stops.map(\.id))
        let separatorDTOs = trip.separators.compactMap { sep -> SeparatorDTO? in
            guard let anchor = sep.afterWaypointID, liveWaypointIDs.contains(anchor) else { return nil }
            return SeparatorDTO(id: sep.id, afterWaypointID: anchor)
        }

        let routingCache = includeRoutingCache
            ? buildRoutingCache(trip: trip, stops: stops, context: context)
            : nil

        return TripDocument(
            schemaVersion: currentSchemaVersion,
            appVersion: appVersion,
            exportedAt: .now,
            trip: tripDTO,
            waypoints: waypointDTOs,
            separators: separatorDTOs,
            routingCache: routingCache
        )
    }

    @MainActor
    private static func buildRoutingCache(
        trip: Trip,
        stops: [Waypoint],
        context: ModelContext
    ) -> RoutingCacheDTO? {
        // Per-pair fresh segments (current engine only).
        var segments: [SegmentDTO] = []
        if stops.count >= 2 {
            let cache = SegmentCache(context)
            for i in 0 ..< stops.count - 1 {
                let from = stops[i].coordinate
                let to = stops[i + 1].coordinate
                guard let seg = cache.lookupFresh(from: from, to: to) else { continue }
                segments.append(SegmentDTO(
                    fromLat: seg.fromLat, fromLon: seg.fromLon,
                    toLat: seg.toLat, toLon: seg.toLon,
                    polylineEncoded: seg.polylineEncoded,
                    distanceMeters: seg.distanceMeters,
                    durationSeconds: seg.durationSeconds,
                    computedAt: seg.computedAt
                ))
            }
        }

        // Whole-trip blob — only if it's current-engine.
        var wholeTrip: WholeTripSnapDTO? = nil
        if trip.snappedRouteRouterVersion == RoutingEngineVersion.current,
           let encoded = trip.snappedRouteEncoded,
           let key = trip.snappedRouteKey {
            wholeTrip = WholeTripSnapDTO(
                polylineEncoded: encoded,
                geometryKey: key,
                computedAt: trip.snappedRouteComputedAt ?? .now
            )
        }

        guard wholeTrip != nil || !segments.isEmpty else { return nil }
        return RoutingCacheDTO(
            routerVersion: RoutingEngineVersion.current,
            wholeTrip: wholeTrip,
            segments: segments
        )
    }
}

// MARK: - Import (TripDocument → inserted Trip)

/// How an imported document maps onto the local store.
enum TripImportMode {
    /// Default. Assign fresh UUIDs to the trip, its waypoints and separators
    /// so the import never clobbers an existing trip — it always lands as a new
    /// copy. Separator anchors are remapped consistently.
    case copy
    /// Keep the document's original UUIDs. If a trip with the same id already
    /// exists it is deleted first (replace). Intended for the device↔simulator
    /// debug round-trip where preserving identity matters.
    case preserveID
}

extension TripDocument {
    /// Materialize the document into the given context and return the inserted
    /// `Trip`. Saves the context before returning. The caller decides whether
    /// to make the result the active trip.
    ///
    /// Tier 3 (blocks/colors/ribbons) is intentionally not restored — it
    /// re-derives from the inserted waypoints + separators. Tier 2 routing
    /// geometry is restored only when `routingCache.routerVersion` matches the
    /// running engine; otherwise it's dropped and the trip will re-snap.
    @MainActor
    @discardableResult
    func importTrip(into context: ModelContext, mode: TripImportMode = .copy) -> Trip {
        // 1. Build the old→new id translation (identity in preserveID mode).
        let preserve = (mode == .preserveID)
        let tripID = preserve ? trip.id : UUID()
        var waypointIDMap: [UUID: UUID] = [:]
        for wp in waypoints {
            waypointIDMap[wp.id] = preserve ? wp.id : UUID()
        }

        // preserveID replace: drop any existing trip with this id first.
        if preserve {
            let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
            if let existing = (try? context.fetch(descriptor))?.first {
                context.delete(existing)
            }
        }

        // 2. Trip identity (Tier 1).
        let newTrip = Trip(
            name: trip.name,
            color: TripColor(rawValue: trip.colorRaw) ?? .amber,
            createdAt: trip.createdAt,
            notes: trip.notes
        )
        newTrip.id = tripID
        context.insert(newTrip)

        // 3. Waypoints (Tier 1).
        for wpDTO in waypoints.sorted(by: { $0.order < $1.order }) {
            let wp = Waypoint(
                order: wpDTO.order,
                coordinate: CLLocationCoordinate2D(latitude: wpDTO.lat, longitude: wpDTO.lon),
                label: wpDTO.label,
                category: wpDTO.category,
                mode: TravelMode(rawValue: wpDTO.modeRaw) ?? .road
            )
            wp.id = waypointIDMap[wpDTO.id] ?? wp.id
            wp.trip = newTrip
            context.insert(wp)
        }
        // Normalize ordering to a clean 0..<n sequence regardless of source.
        newTrip.renumberWaypoints()

        // 4. Separators (Tier 1). Drop any whose anchor didn't survive the map
        //    — an external file may reference a waypoint it didn't include.
        for sepDTO in separators {
            guard let oldAnchor = sepDTO.afterWaypointID,
                  let newAnchor = waypointIDMap[oldAnchor] else { continue }
            let sep = BlockSeparator(afterWaypointID: newAnchor)
            sep.id = preserve ? sepDTO.id : UUID()
            sep.trip = newTrip
            context.insert(sep)
        }

        // 5. Tier 2 routing cache — restored only if current-engine.
        restoreRoutingCache(into: newTrip, context: context)

        try? context.save()
        return newTrip
    }

    @MainActor
    private func restoreRoutingCache(into newTrip: Trip, context: ModelContext) {
        guard let cache = routingCache,
              cache.routerVersion == RoutingEngineVersion.current
        else { return }   // absent or stale-engine → drop; trip re-snaps online.

        // Per-pair segments → global segment cache (coord-keyed, version-stamped).
        let segCache = SegmentCache(context)
        for seg in cache.segments {
            guard let coords = PolylineCodec.decode(seg.polylineEncoded), coords.count >= 2 else { continue }
            segCache.store(
                from: CLLocationCoordinate2D(latitude: seg.fromLat, longitude: seg.fromLon),
                to: CLLocationCoordinate2D(latitude: seg.toLat, longitude: seg.toLon),
                polyline: coords,
                distanceMeters: seg.distanceMeters,
                durationSeconds: seg.durationSeconds,
                at: seg.computedAt
            )
        }

        // Whole-trip blob → set fields directly so `computedAt` is preserved
        // (setSnappedCoords would stamp it to now). The coord-based geometryKey
        // is still valid because the imported coordinates are unchanged.
        if let blob = cache.wholeTrip {
            newTrip.snappedRouteEncoded = blob.polylineEncoded
            newTrip.snappedRouteKey = blob.geometryKey
            newTrip.snappedRouteComputedAt = blob.computedAt
            newTrip.snappedRouteRouterVersion = RoutingEngineVersion.current
        }
    }
}
