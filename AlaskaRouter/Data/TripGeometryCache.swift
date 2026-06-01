// Single-slot memoization for the trip's heavy geometry computations
// (AlaskaRouter-bhs4).
//
// Both `Trip.legDistancesMeters` and `Trip.routeRibbons` are O(W × P) — W
// waypoints, P snapped-polyline points. For an Alaska trip with ~40 stops
// and a several-thousand-point OSRM polyline they each cost hundreds of
// thousands to millions of inner ops. They were being recomputed on every
// SwiftUI body re-render (multiple call sites in TripBottomSheet, RootView,
// and inside ExpeditionMapView's unsafeMapViewControllerModifier closure),
// which made the app unusably sluggish — typing into the rename-trip alert
// would lag because the bottom-sheet body re-rendered and ran all three
// distance calls per keystroke.
//
// One slot per accessor is enough: once stops, snap, separators, or trip
// color change, the prior result is stale. Hits are free; misses recompute
// exactly as before.

import Foundation
import CoreLocation

@MainActor
final class TripGeometryCache {
    static let shared = TripGeometryCache()
    private init() {}

    private var legsKey: String = ""
    private var legsValue: [Double] = []

    private var ribbonsKey: String = ""
    private var ribbonsValue: [RouteRibbon] = []

    func legDistances(for trip: Trip, snappedCoords: [CLLocationCoordinate2D]?) -> [Double] {
        let key = Self.legsFingerprint(trip: trip, snapped: snappedCoords)
        if key == legsKey { return legsValue }
        legsValue = trip.legDistancesMeters(snappedCoords: snappedCoords)
        legsKey = key
        return legsValue
    }

    func totalDistance(for trip: Trip, snappedCoords: [CLLocationCoordinate2D]?) -> Double {
        legDistances(for: trip, snappedCoords: snappedCoords).reduce(0, +)
    }

    func blockDistance(_ block: TripBlock, for trip: Trip, snappedCoords: [CLLocationCoordinate2D]?) -> Double {
        let legs = legDistances(for: trip, snappedCoords: snappedCoords)
        guard !legs.isEmpty else { return 0 }
        let stops = trip.orderedWaypoints
        let blockStopIDs = Set(block.waypoints.map(\.id))
        var total = 0.0
        for i in 0 ..< stops.count - 1 where blockStopIDs.contains(stops[i + 1].id) {
            total += legs[i]
        }
        return total
    }

    func routeRibbons(
        for trip: Trip,
        snappedCoords: [CLLocationCoordinate2D]?,
        pendingPairIndices: Set<Int>? = nil
    ) -> [RouteRibbon] {
        let key = Self.ribbonsFingerprint(
            trip: trip,
            snapped: snappedCoords,
            pending: pendingPairIndices
        )
        if key == ribbonsKey { return ribbonsValue }
        ribbonsValue = trip.routeRibbons(
            snappedCoords: snappedCoords,
            pendingPairIndices: pendingPairIndices
        )
        ribbonsKey = key
        return ribbonsValue
    }

    private static func legsFingerprint(trip: Trip, snapped: [CLLocationCoordinate2D]?) -> String {
        var s = ""
        for wp in trip.orderedWaypoints {
            s += String(format: "%.5f,%.5f|", wp.lat, wp.lon)
        }
        s += snapFingerprint(snapped)
        return s
    }

    private static func ribbonsFingerprint(
        trip: Trip,
        snapped: [CLLocationCoordinate2D]?,
        pending: Set<Int>?
    ) -> String {
        var s = legsFingerprint(trip: trip, snapped: snapped)
        s += "@blocks="
        let anchors = trip.separators.compactMap(\.afterWaypointID).map(\.uuidString).sorted()
        for a in anchors { s += a + "," }
        s += "@color=" + trip.colorRaw
        if let pending, !pending.isEmpty {
            s += "@pending=" + pending.sorted().map(String.init).joined(separator: ",")
        }
        return s
    }

    private static func snapFingerprint(_ snapped: [CLLocationCoordinate2D]?) -> String {
        guard let snap = snapped, !snap.isEmpty else { return "@snap=nil" }
        let f = snap.first!
        let l = snap.last!
        let m = snap[snap.count / 2]
        return String(
            format: "@snap=%d;%.4f,%.4f;%.4f,%.4f;%.4f,%.4f",
            snap.count,
            f.latitude, f.longitude,
            m.latitude, m.longitude,
            l.latitude, l.longitude
        )
    }
}
