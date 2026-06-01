// Road-stretch length computation + distance formatting (AlaskaRouter-ssl1).
//
// Distances come from the snapped OSRM polyline when available — summed along
// each leg's slice so curves count — and fall back to straight-line haversine
// between waypoints when there's no snap. The previous trip-total stat was
// straight-line only (it under-counted the real road); these helpers give the
// per-leg / per-block / total road lengths the bottom sheet needs for planning.

import Foundation
import CoreLocation

extension Trip {

    /// Monotonic waypoint → polyline-index mapping. OSRM's merged polyline
    /// visits the trip's waypoints in order (retracing for return legs), so a
    /// forward-only cursor that snaps each waypoint to the closest point
    /// at-or-after the previous one handles retraces correctly.
    ///
    /// Shared by `legDistancesMeters`, `routeRibbons` and the per-segment
    /// cache decomposition in the snap pipeline. Pure function — no `Trip`
    /// state — `static` so the snap pipeline can call it on the raw OSRM
    /// response before any SwiftData state has been written.
    static func monotonicWaypointIndexes(
        polyline: [CLLocationCoordinate2D],
        waypoints: [CLLocationCoordinate2D]
    ) -> [Int] {
        guard !polyline.isEmpty else { return [] }
        var cursor = 0
        var result: [Int] = []
        result.reserveCapacity(waypoints.count)
        for wp in waypoints {
            var bestIdx = cursor
            var bestDist = Double.infinity
            for i in cursor ..< polyline.count {
                let d = SmartInsert.haversine(polyline[i], wp)
                if d < bestDist { bestDist = d; bestIdx = i }
            }
            result.append(bestIdx)
            cursor = bestIdx
        }
        return result
    }

    /// Per-leg length in metres — one entry per consecutive ordered-stop pair
    /// (count = stops − 1). Leg `i` is the stretch from stop `i` to stop `i+1`.
    /// Uses the snapped polyline (mirroring routeRibbons' monotonic
    /// waypoint→polyline cursor so retraces map correctly); straight-line when
    /// unsnapped.
    func legDistancesMeters(snappedCoords: [CLLocationCoordinate2D]?) -> [Double] {
        let stops = orderedWaypoints
        guard stops.count >= 2 else { return [] }

        guard let snap = snappedCoords, snap.count >= 2 else {
            return (0 ..< stops.count - 1).map {
                SmartInsert.haversine(stops[$0].coordinate, stops[$0 + 1].coordinate)
            }
        }

        let idx = Trip.monotonicWaypointIndexes(
            polyline: snap,
            waypoints: stops.map(\.coordinate)
        )

        return (0 ..< stops.count - 1).map { i in
            let lo = min(idx[i], idx[i + 1])
            let hi = max(idx[i], idx[i + 1])
            guard hi > lo else { return 0 }
            var m = 0.0
            for k in lo ..< hi { m += SmartInsert.haversine(snap[k], snap[k + 1]) }
            return m
        }
    }

    /// Total road length in metres.
    func totalDistanceMeters(snappedCoords: [CLLocationCoordinate2D]?) -> Double {
        legDistancesMeters(snappedCoords: snappedCoords).reduce(0, +)
    }

    /// Distance in metres covered by a block — the sum of legs whose
    /// DESTINATION stop is in the block. Matches the ribbon-coloring
    /// convention (the road leaving block N's last stop belongs to block N+1),
    /// so the connector between blocks is attributed to the block it enters.
    func blockDistanceMeters(_ block: TripBlock, snappedCoords: [CLLocationCoordinate2D]?) -> Double {
        let legs = legDistancesMeters(snappedCoords: snappedCoords)
        guard !legs.isEmpty else { return 0 }
        let stops = orderedWaypoints
        let blockStopIDs = Set(block.waypoints.map(\.id))
        var total = 0.0
        for i in 0 ..< stops.count - 1 where blockStopIDs.contains(stops[i + 1].id) {
            total += legs[i]
        }
        return total
    }
}

/// Formats a metre distance into a short display string in the user's chosen
/// unit. Sub-10 values get one decimal so a short hop never reads "0 km".
enum DistanceFormat {
    static func string(meters: Double, useMiles: Bool) -> String {
        let value = useMiles ? meters / 1609.344 : meters / 1000.0
        let unit = useMiles ? "mi" : "km"
        if value < 10 { return String(format: "%.1f %@", value, unit) }
        return "\(Int(value.rounded())) \(unit)"
    }
}
