// Trip lifecycle helpers — bootstrap on first launch, persist the active trip
// across launches, generate default names. The SwiftData @Model layer stays
// dumb; this is the only place that knows about app-level trip state.

import Foundation
import SwiftData

enum TripStore {
    private static let activeTripIDKey = "activeTripID"

    /// On first launch (zero trips in the store), creates one empty trip
    /// named "Trip from <today>" and marks it active. After this returns,
    /// `activeTripID` is guaranteed non-nil and points at a real trip.
    @MainActor
    static func bootstrapIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Trip>())) ?? 0
        guard count == 0 else {
            // We already have trips. Make sure activeTripID still resolves;
            // if it doesn't, point at trips.first.
            ensureActiveResolves(in: context)
            return
        }
        let trip = Trip(name: defaultName(in: context))
        context.insert(trip)
        try? context.save()
        setActive(trip)
    }

    /// Generates a default name "Trip from YYYY-MM-DD", suffixing "(2)", "(3)",
    /// etc. if that exact name already exists.
    static func defaultName(in context: ModelContext) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let base = "Trip from \(df.string(from: .now))"
        let existing = (try? context.fetch(FetchDescriptor<Trip>()).map(\.name)) ?? []
        if !existing.contains(base) { return base }
        for n in 2...99 {
            let candidate = "\(base) (\(n))"
            if !existing.contains(candidate) { return candidate }
        }
        return base
    }

    static var activeTripID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: activeTripIDKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: activeTripIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeTripIDKey)
            }
        }
    }

    static func setActive(_ trip: Trip) {
        activeTripID = trip.id
    }

    /// Given the @Query-fetched trip list, returns the one matching
    /// `activeTripID`, or `trips.first` as a fallback.
    static func resolveActive(from trips: [Trip]) -> Trip? {
        if let id = activeTripID, let match = trips.first(where: { $0.id == id }) {
            return match
        }
        return trips.first
    }

    /// If the stored activeTripID points at a non-existent trip (e.g. after a
    /// delete), reset it to trips.first.
    @MainActor
    static func ensureActiveResolves(in context: ModelContext) {
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        if let id = activeTripID, trips.contains(where: { $0.id == id }) { return }
        if let first = trips.first {
            setActive(first)
        } else {
            activeTripID = nil
        }
    }

    /// Inserts a new empty trip with the default name, marks it active.
    /// Returns the trip so the caller can route the UI to it.
    @MainActor
    @discardableResult
    static func createEmpty(in context: ModelContext) -> Trip {
        let trip = Trip(name: defaultName(in: context))
        context.insert(trip)
        try? context.save()
        setActive(trip)
        return trip
    }

    /// Deletes a trip. If it was active, falls back to the most-recently-created
    /// remaining trip. If no trips remain, bootstraps a fresh empty one so the
    /// app is never trip-less.
    @MainActor
    static func delete(_ trip: Trip, in context: ModelContext) {
        let wasActive = (trip.id == activeTripID)
        context.delete(trip)
        try? context.save()
        if wasActive {
            let remaining = (try? context.fetch(
                FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            )) ?? []
            if let next = remaining.first {
                setActive(next)
            } else {
                _ = createEmpty(in: context)
            }
        }
    }

    /// Renames a trip. Empty / whitespace-only names are ignored (no-op).
    @MainActor
    static func rename(_ trip: Trip, to newName: String, in context: ModelContext) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        trip.name = trimmed
        try? context.save()
    }
}
