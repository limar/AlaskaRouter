import CoreLocation
import SwiftData
@testable import AlaskaRouter

enum TestFactories {
    static func waypoint(
        order: Int,
        latitude: Double,
        longitude: Double,
        label: String? = nil,
        category: String? = nil
    ) -> Waypoint {
        Waypoint(
            order: order,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            label: label ?? "Stop \(order + 1)",
            category: category
        )
    }

    static func trip(
        name: String = "Test Trip",
        color: TripColor = .amber,
        stops: [(latitude: Double, longitude: Double, label: String)],
        separatorAfterOrders: [Int] = []
    ) -> Trip {
        let trip = Trip(name: name, color: color)
        let waypoints = stops.enumerated().map { index, stop in
            waypoint(order: index, latitude: stop.latitude, longitude: stop.longitude, label: stop.label)
        }
        trip.waypoints = waypoints
        for waypoint in waypoints {
            waypoint.trip = trip
        }

        let separators = separatorAfterOrders.compactMap { order -> BlockSeparator? in
            guard let anchor = waypoints.first(where: { $0.order == order }) else { return nil }
            let separator = BlockSeparator(afterWaypointID: anchor.id)
            separator.trip = trip
            return separator
        }
        trip.separators = separators
        return trip
    }

    @MainActor
    static func inMemoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Trip.self,
            Waypoint.self,
            BlockSeparator.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
