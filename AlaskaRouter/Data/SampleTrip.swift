// First-launch seeding. If the SwiftData store is empty, insert the demo
// Parks Highway trip we've been using throughout the spike rounds — five
// waypoints from Cantwell north to Fairbanks. Lets the user see something
// real on first launch without needing the search-and-add flow to exist yet.

import Foundation
import SwiftData
import CoreLocation

enum SampleTrip {
    static let parksHighwayWaypoints: [(name: String, lat: Double, lon: Double, category: String?)] = [
        ("Cantwell",             63.3956, -148.9075, "settlement"),
        ("Denali Park Entrance", 63.7298, -148.9128, "visitor_center"),
        ("Healy",                63.8625, -148.9706, "settlement"),
        ("Nenana",               64.5631, -149.0925, "river_crossing"),
        ("Fairbanks",            64.8378, -147.7164, "settlement_major"),
    ]

    /// Inserts the Parks Highway trip if and only if the store has zero trips.
    static func seedIfEmpty(in context: ModelContext) {
        let existingCount = (try? context.fetchCount(FetchDescriptor<Trip>())) ?? 0
        guard existingCount == 0 else { return }

        let trip = Trip(name: "Dalton Highway — North", color: .amber)
        context.insert(trip)

        var waypoints: [Waypoint] = []
        for (i, wp) in parksHighwayWaypoints.enumerated() {
            let w = Waypoint(
                order: i,
                coordinate: .init(latitude: wp.lat, longitude: wp.lon),
                label: wp.name,
                category: wp.category
            )
            w.trip = trip
            context.insert(w)
            waypoints.append(w)
        }

        // Optional dev seed: insert a block separator after stop index 2
        // (Healy), splitting into "Cantwell → Healy" / "Nenana → Fairbanks".
        if UserDefaults.standard.bool(forKey: "seedDemoSeparator"),
           waypoints.count >= 4 {
            let sep = BlockSeparator(afterWaypointID: waypoints[2].id)
            sep.trip = trip
            context.insert(sep)
        }

        // Optional dev seed for AlaskaRouter-9axu / -3bot — append the same
        // 5 stops in reverse order (excluding the last to avoid two
        // consecutive Fairbanks stops). Produces a synthetic out-and-back
        // trip where every segment overlaps with its return counterpart,
        // exercising the multi-pass offset rendering.
        if UserDefaults.standard.bool(forKey: "seedDemoReturnLeg"),
           waypoints.count >= 2 {
            let reverse = waypoints.dropLast().reversed()
            var nextOrder = waypoints.count
            for source in reverse {
                let w = Waypoint(
                    order: nextOrder,
                    coordinate: source.coordinate,
                    label: source.label,
                    category: source.category
                )
                w.trip = trip
                context.insert(w)
                nextOrder += 1
            }
        }

        // Optional dev seed for AlaskaRouter-3bot — three-leg back-and-forth
        // (forward, reverse, forward-again). Combine with seedDemoReturnLeg.
        // Stresses the multi-pass offset with three lanes on the shared road
        // (two forward on one side, one backward on the other).
        if UserDefaults.standard.bool(forKey: "seedDemoTripleLeg"),
           waypoints.count >= 2 {
            let currentMaxOrder = trip.waypoints.map(\.order).max() ?? (waypoints.count - 1)
            var nextOrder = currentMaxOrder + 1
            // Skip the first stop to avoid two consecutive Cantwell stops.
            for source in waypoints.dropFirst() {
                let w = Waypoint(
                    order: nextOrder,
                    coordinate: source.coordinate,
                    label: source.label,
                    category: source.category
                )
                w.trip = trip
                context.insert(w)
                nextOrder += 1
            }
        }

        try? context.save()
    }
}
