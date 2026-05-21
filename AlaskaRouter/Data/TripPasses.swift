// AlaskaRouter-3bot — Pass-aware route rendering, step-by-step rebuild.
//
// Step 1: just return ONE polyline covering the whole trip route. No
// multi-pass identification yet, no per-leg fragmentation, no offset
// math. The renderer treats this single polyline as the route's full
// extent at offset 0.
//
// Subsequent steps will add: pass identification, per-pass full-extent
// polylines, absolute lineOffset values, color-per-block overlay.

import Foundation
import CoreLocation

extension Trip {
    /// The trip's full driven path as a single polyline.
    /// - If `snappedCoords` is provided (OSRM result), returns it verbatim
    ///   (it already retraces for multi-pass routes).
    /// - Otherwise returns a straight-line polyline through the trip's
    ///   waypoints in order (offline / pre-snap fallback).
    /// - Returns nil when the trip has fewer than 2 waypoints (nothing to draw).
    func fullRouteCoords(snappedCoords: [CLLocationCoordinate2D]?) -> [CLLocationCoordinate2D]? {
        if let snap = snappedCoords, snap.count >= 2 {
            return snap
        }
        let stops = orderedWaypoints
        guard stops.count >= 2 else { return nil }
        return stops.map(\.coordinate)
    }
}
