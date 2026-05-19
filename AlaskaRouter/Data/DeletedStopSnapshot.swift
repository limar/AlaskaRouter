// Captured copy of a Waypoint right before it's deleted, used to power the
// "Removed from trip — Undo" toast (see TripEditToast). We can't keep the
// SwiftData reference alive past `modelContext.delete(_:)`, so the sheet
// snapshots the fields we'd need to recreate the stop.

import Foundation
import CoreLocation

struct DeletedStopSnapshot: Identifiable, Equatable {
    let id: UUID                       // original Waypoint.id
    let order: Int                     // position in the trip's ordered sequence
    let coordinate: CLLocationCoordinate2D
    let label: String?
    let category: String?

    static func == (lhs: DeletedStopSnapshot, rhs: DeletedStopSnapshot) -> Bool {
        lhs.id == rhs.id
    }
}
