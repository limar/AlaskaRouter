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
