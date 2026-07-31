// SwiftData persistence schema for AlaskaRouter v1.
//
// Minimal v1 surface — Trip + Waypoint. RouteSegment (with cached snap-to-road
// geometry) is deferred to the Routing layer iteration. The TravelMode and
// SegmentGeometry enums are defined here so the schema is forward-compatible
// when segment caching lands. See memory: project_routing_strategy.md.

import Foundation
import SwiftData
import CoreLocation

@Model
final class Trip {
    var id: UUID = UUID()
    var name: String = ""
    var colorRaw: String = TripColor.amber.rawValue
    var createdAt: Date = Date()
    var notes: String = ""

    /// Read-only marker (AlaskaRouter-ijy9). A finished trip is a memory, and
    /// nothing used to stop a stray drag or swipe from quietly rewriting one.
    ///
    /// Locked freezes the *itinerary* — stops, their order, and block
    /// separators. It deliberately does NOT freeze the drawn route: a leg that
    /// fell back to a straight dashed line offline still refreshes to a real
    /// road when the network returns. That changes how the trip is drawn, not
    /// what the trip is, and a locked trip stuck with dashed legs forever is a
    /// poor memento.
    ///
    /// Defaulted, like every other property here, so SwiftData can migrate an
    /// existing store without a versioned migration step. See
    /// AlaskaRouter-tpoo for the one
    /// migration that has bitten this schema before.
    var isLocked: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Waypoint.trip)
    var waypoints: [Waypoint] = []

    @Relationship(deleteRule: .cascade, inverse: \BlockSeparator.trip)
    var separators: [BlockSeparator] = []

    // MARK: - Snapped-route cache (AlaskaRouter-kp9h)
    //
    // The exact ORS/OSRM-routed polyline computed while online, persisted so
    // the trip still renders along real roads when reopened OFFLINE. Three
    // fields so we know:
    //   - what we cached    (snappedRouteEncoded — JSON [[lat,lon],…])
    //   - what it's for     (snappedRouteKey — matches RootView.tripGeometryKey
    //                        at time of fetch; cache is invalid the moment
    //                        the waypoint sequence changes)
    //   - when we cached it (snappedRouteComputedAt — for staleness UI later)
    // Empty / nil = no cached snap; renderer falls back to spline/straight.
    var snappedRouteEncoded: String? = nil
    var snappedRouteKey: String? = nil
    var snappedRouteComputedAt: Date? = nil
    /// Routing engine version stamp (AlaskaRouter-y3g3). Bumping
    /// `RoutingEngineVersion.current` invalidates rows stamped with an
    /// older value — cachedSnappedCoords returns nil on mismatch and the
    /// snap pipeline silently re-fetches with the new engine.
    var snappedRouteRouterVersion: Int = 0

    init(name: String, color: TripColor = .amber, createdAt: Date = .now, notes: String = "") {
        self.name = name
        self.colorRaw = color.rawValue
        self.createdAt = createdAt
        self.notes = notes
    }

    var color: TripColor {
        get { TripColor(rawValue: colorRaw) ?? .amber }
        set { colorRaw = newValue.rawValue }
    }

    /// Waypoints sorted by their `order` for stable rendering.
    var orderedWaypoints: [Waypoint] {
        waypoints.sorted { $0.order < $1.order }
    }

    /// Compact waypoint order values after deleting or moving stops.
    ///
    /// AlaskaRouter-lqfq: SwiftData keeps a just-deleted waypoint visible in
    /// the relationship until the context save completes, so deletion paths
    /// pass its id here to keep the removed stop out of the numbering pass.
    /// Without this exclusion, deleting the middle of A → Middle → B would
    /// renumber [A:0, Middle:1, B:2] and leave B displaying as #3.
    func renumberWaypoints(excluding excludedID: UUID? = nil) {
        renumberWaypoints(excluding: excludedID.map { Set([$0]) } ?? [])
    }

    func renumberWaypoints(excluding excludedIDs: Set<UUID>) {
        let remaining = orderedWaypoints.filter { !excludedIDs.contains($0.id) }
        for (index, waypoint) in remaining.enumerated() {
            waypoint.order = index
        }
    }

    // MARK: - Snapped-route cache helpers (kp9h)

    /// Decoded snapped polyline if the cache is non-empty AND its key matches
    /// the caller's current `tripGeometryKey`. Returns nil otherwise — the
    /// caller should then fall back to spline/straight and trigger a fresh
    /// snap (which will refill the cache on success).
    func cachedSnappedCoords(for currentGeometryKey: String) -> [CLLocationCoordinate2D]? {
        guard let encoded = snappedRouteEncoded,
              let storedKey = snappedRouteKey,
              storedKey == currentGeometryKey,
              snappedRouteRouterVersion == RoutingEngineVersion.current
        else { return nil }
        return Trip.decodeSnap(encoded)
    }

    /// Write a fresh snap into the cache. Caller is responsible for SwiftData
    /// `modelContext.save()` (or letting the context auto-save at suspend).
    func setSnappedCoords(_ coords: [CLLocationCoordinate2D], geometryKey: String, at now: Date = .now) {
        snappedRouteEncoded = Trip.encodeSnap(coords)
        snappedRouteKey = geometryKey
        snappedRouteComputedAt = now
        snappedRouteRouterVersion = RoutingEngineVersion.current
    }

    /// Wipe the cache — call when waypoint sequence changes if the caller
    /// wants the saved-state to immediately reflect "no snap available".
    /// (The cache also self-invalidates by key mismatch, so calling this is
    /// optional; it just avoids carrying a stale blob until the next snap.)
    func clearSnappedCache() {
        snappedRouteEncoded = nil
        snappedRouteKey = nil
        snappedRouteComputedAt = nil
    }

    /// Delegate to PolylineCodec so RouteSegment can reuse the same format.
    private static func encodeSnap(_ coords: [CLLocationCoordinate2D]) -> String? {
        PolylineCodec.encode(coords)
    }

    private static func decodeSnap(_ encoded: String) -> [CLLocationCoordinate2D]? {
        PolylineCodec.decode(encoded)
    }
}

/// Per-pair routing cache row (AlaskaRouter-un6b). A directed pair
/// `(from → to)` maps to a snapped polyline plus its OSRM-reported
/// distance and duration. One-way roads matter, so `(A→B)` and `(B→A)`
/// are stored as distinct rows.
///
/// Coordinates in the lookup key are rounded to 5 decimals (~1.1 m) so
/// a re-geocoded stop at the same place still hits. The `key` field
/// holds the canonical "lat,lon→lat,lon" string for fast equality
/// lookups via a SwiftData predicate.
@Model
final class RouteSegment {
    @Attribute(.unique) var key: String = ""
    var fromLat: Double = 0
    var fromLon: Double = 0
    var toLat: Double = 0
    var toLon: Double = 0
    var polylineEncoded: String = ""
    var distanceMeters: Double = 0
    var durationSeconds: Double = 0
    var computedAt: Date = Date()
    /// Routing engine version stamp (AlaskaRouter-y3g3). The planner
    /// treats a row whose `routerVersion` doesn't match
    /// `RoutingEngineVersion.current` as a cache miss, so an engine swap
    /// (e.g. OSRM → Valhalla) silently invalidates the prior cache
    /// without a destructive wipe.
    var routerVersion: Int = 0
    /// (AlaskaRouter-2i03) Terminal "no route" verdict. `true` means the
    /// router was asked and answered that this directed pair has no
    /// drivable path (e.g. a stop at the off-road geographic centre of
    /// Denali Park). The row carries an empty `polylineEncoded` and acts
    /// as a *negative cache*: the planner renders a dashed straight line
    /// for it (no road geometry) but never re-fetches it. Because the
    /// lookup key is coordinate-based, moving either stop yields a new key
    /// → cache miss → a fresh attempt; and `routerVersion` invalidation
    /// re-probes the pair after an engine swap. Defaulted so existing
    /// rows (and SwiftData lightweight migration) read it as `false`.
    var isUnroutable: Bool = false

    init(key: String,
         fromLat: Double, fromLon: Double,
         toLat: Double, toLon: Double,
         polylineEncoded: String,
         distanceMeters: Double,
         durationSeconds: Double,
         computedAt: Date = .now,
         routerVersion: Int = RoutingEngineVersion.current,
         isUnroutable: Bool = false)
    {
        self.key = key
        self.fromLat = fromLat
        self.fromLon = fromLon
        self.toLat = toLat
        self.toLon = toLon
        self.polylineEncoded = polylineEncoded
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.computedAt = computedAt
        self.routerVersion = routerVersion
        self.isUnroutable = isUnroutable
    }

    var coordinates: [CLLocationCoordinate2D] {
        PolylineCodec.decode(polylineEncoded) ?? []
    }
}

/// A user-placed boundary between two consecutive stops, splitting the trip
/// into multiple itinerary blocks (days / stretches). A separator sits AFTER
/// the waypoint with `afterWaypointID` in the ordered sequence; the implicit
/// first block runs from the trip start up to the first separator.
@Model
final class BlockSeparator {
    var id: UUID = UUID()
    /// The waypoint this separator sits AFTER in the ordered sequence.
    /// If nil, the separator is degenerate (no anchor); should be cleaned up.
    var afterWaypointID: UUID?
    var trip: Trip?

    init(afterWaypointID: UUID) {
        self.afterWaypointID = afterWaypointID
    }
}

@Model
final class Waypoint {
    var id: UUID = UUID()
    var order: Int = 0
    var lat: Double = 0
    var lon: Double = 0
    var label: String?
    /// FTS5-derived category (`fuel`, `visitor_center`, `peak`, ...).
    var category: String?
    /// Forward-compat for multi-modal trips. v1 only uses `.road`.
    var modeRaw: String = TravelMode.road.rawValue
    var trip: Trip?

    init(order: Int, coordinate: CLLocationCoordinate2D, label: String? = nil,
         category: String? = nil, mode: TravelMode = .road)
    {
        self.order = order
        self.lat = coordinate.latitude
        self.lon = coordinate.longitude
        self.label = label
        self.category = category
        self.modeRaw = mode.rawValue
    }

    var coordinate: CLLocationCoordinate2D {
        get { .init(latitude: lat, longitude: lon) }
        set { lat = newValue.latitude; lon = newValue.longitude }
    }

    var mode: TravelMode {
        get { TravelMode(rawValue: modeRaw) ?? .road }
        set { modeRaw = newValue.rawValue }
    }
}

// MARK: - Value types

/// Trip accent / route line color.
enum TripColor: String, Codable, CaseIterable {
    case amber, teal, terracotta, sage, indigo, slate

    /// Mock-handoff palette (see design/mocks/map.jsx). Saturated atlas-style
    /// colors that work as both a UI accent and a translucent route-line wash.
    var swiftUIColor: ColorTuple {
        switch self {
        case .amber:      return .init(red: 0.760, green: 0.255, blue: 0.047) // #c2410c burnt orange
        case .teal:       return .init(red: 0.114, green: 0.306, blue: 0.847) // #1d4ed8 royal blue
        case .terracotta: return .init(red: 0.882, green: 0.114, blue: 0.282) // #e11d48 rose
        case .sage:       return .init(red: 0.082, green: 0.502, blue: 0.239) // #15803d forest green
        case .indigo:     return .init(red: 0.427, green: 0.157, blue: 0.851) // #6d28d9 violet
        case .slate:      return .init(red: 0.216, green: 0.255, blue: 0.318) // #374151 charcoal
        }
    }
    struct ColorTuple { let red, green, blue: Double }
}

/// Forward-compatible travel mode (v1 only uses `.road`).
enum TravelMode: String, Codable {
    case road, flight, ferry, walking
}

/// Segment geometry persistence form (deferred to RouteSegment when we wire
/// the Routing layer with OSRM/ORS caching). Listed here so the v1 schema can
/// reference it later without breaking changes.
enum SegmentGeometry: Codable, Equatable {
    case straight
    case spline
    case snapped(encodedPolyline: String, computedAt: Date)
}
