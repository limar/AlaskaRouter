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

    // MARK: - Snapped-route cache helpers (kp9h)

    /// Decoded snapped polyline if the cache is non-empty AND its key matches
    /// the caller's current `tripGeometryKey`. Returns nil otherwise — the
    /// caller should then fall back to spline/straight and trigger a fresh
    /// snap (which will refill the cache on success).
    func cachedSnappedCoords(for currentGeometryKey: String) -> [CLLocationCoordinate2D]? {
        guard let encoded = snappedRouteEncoded,
              let storedKey = snappedRouteKey,
              storedKey == currentGeometryKey
        else { return nil }
        return Trip.decodeSnap(encoded)
    }

    /// Write a fresh snap into the cache. Caller is responsible for SwiftData
    /// `modelContext.save()` (or letting the context auto-save at suspend).
    func setSnappedCoords(_ coords: [CLLocationCoordinate2D], geometryKey: String, at now: Date = .now) {
        snappedRouteEncoded = Trip.encodeSnap(coords)
        snappedRouteKey = geometryKey
        snappedRouteComputedAt = now
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

    /// Encode an array of CLLocationCoordinate2D as a JSON string of
    /// [[lat,lon],…] pairs. Chosen for debuggability over compactness —
    /// a 2000-point Alaska polyline encodes to ~50 KB JSON vs ~10 KB
    /// Google-encoded; size is well within SwiftData's comfort zone and
    /// the JSON survives schema migrations / inspection painlessly.
    private static func encodeSnap(_ coords: [CLLocationCoordinate2D]) -> String? {
        let pairs: [[Double]] = coords.map { [$0.latitude, $0.longitude] }
        guard let data = try? JSONSerialization.data(withJSONObject: pairs) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeSnap(_ encoded: String) -> [CLLocationCoordinate2D]? {
        guard let data = encoded.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[Double]]
        else { return nil }
        return arr.compactMap { p in
            guard p.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: p[0], longitude: p[1])
        }
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
