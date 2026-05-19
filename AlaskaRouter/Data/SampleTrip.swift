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

        try? context.save()
    }
}
