// Geographic "cheapest-edge" insertion algorithm for adding a new waypoint
// into an existing trip route. Inserts the candidate at the position that
// minimizes the haversine detour cost.
//
// For a route W₁ → W₂ → ... → Wₙ and a candidate P, considers n+1 positions
// (before W₁, between each adjacent pair, after Wₙ) and picks the lowest cost:
//   cost(0)    = haversine(P, W₁)
//   cost(i)    = haversine(W[i-1], P) + haversine(P, W[i]) - haversine(W[i-1], W[i])    for 1 ≤ i ≤ n-1
//   cost(n)    = haversine(Wₙ, P)
//
// Notes:
//   - For trips with < 2 waypoints, returns position = waypoints.count (append).
//   - Classic O(n) TSP "cheapest insertion" heuristic. Works very well for
//     mostly-linear expedition routes; would need more for highly tangled ones.

import Foundation
import CoreLocation
import SwiftData

enum SmartInsert {

    /// Position at which a new waypoint with `coordinate` should be inserted
    /// into `waypoints` (already sorted by .order). Returns an index in 0...n.
    static func position(forCoordinate coordinate: CLLocationCoordinate2D,
                         in waypoints: [Waypoint]) -> Int {
        let n = waypoints.count
        if n < 2 { return n }   // append (handles 0- and 1-stop trips)

        var best = 0
        var bestCost = Double.infinity
        let coords = waypoints.map(\.coordinate)

        for i in 0...n {
            let cost: Double
            if i == 0 {
                cost = haversine(coordinate, coords[0])
            } else if i == n {
                cost = haversine(coords[n - 1], coordinate)
            } else {
                let a = coords[i - 1]
                let b = coords[i]
                cost = haversine(a, coordinate) + haversine(coordinate, b) - haversine(a, b)
            }
            if cost < bestCost {
                bestCost = cost
                best = i
            }
        }
        return best
    }

    /// Inserts a Waypoint at the smart position, renumbering `.order` on
    /// subsequent waypoints so the sequence stays contiguous. Returns the
    /// inserted Waypoint (already linked to the trip + saved to context).
    @MainActor
    static func insertSmart(
        coordinate: CLLocationCoordinate2D,
        label: String?,
        category: String?,
        into trip: Trip,
        using context: ModelContext
    ) -> Waypoint {
        let existing = trip.orderedWaypoints
        let pos = position(forCoordinate: coordinate, in: existing)

        let new = Waypoint(order: pos, coordinate: coordinate, label: label, category: category)
        new.trip = trip
        context.insert(new)

        // Shift order on everything at or after the insertion point.
        for wp in existing where wp.order >= pos {
            wp.order += 1
        }
        try? context.save()
        return new
    }

    // MARK: - Haversine

    private static let earthRadiusMeters: Double = 6_371_000

    static func haversine(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let dφ = (b.latitude - a.latitude) * .pi / 180
        let dλ = (b.longitude - a.longitude) * .pi / 180
        let sinDφ2 = sin(dφ / 2)
        let sinDλ2 = sin(dλ / 2)
        let h = sinDφ2 * sinDφ2 + cos(φ1) * cos(φ2) * sinDλ2 * sinDλ2
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }
}
