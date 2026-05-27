import SwiftData
import XCTest
@testable import AlaskaRouter

@MainActor
final class TripStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TripStore.activeTripID = nil
    }

    override func tearDown() {
        TripStore.activeTripID = nil
        super.tearDown()
    }

    func testBootstrapCreatesAndActivatesFirstTrip() throws {
        let context = try TestFactories.inMemoryContext()

        TripStore.bootstrapIfNeeded(in: context)
        let trips = try fetchTrips(in: context)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(TripStore.activeTripID, trips[0].id)
        XCTAssertTrue(trips[0].name.hasPrefix("Trip from "))
    }

    func testDefaultNameAddsSuffixWhenBaseNameExists() throws {
        let context = try TestFactories.inMemoryContext()
        let base = TripStore.defaultName(in: context)
        context.insert(Trip(name: base))
        try context.save()

        XCTAssertEqual(TripStore.defaultName(in: context), "\(base) (2)")
    }

    func testDeleteActiveTripFallsBackToMostRecentRemainingTrip() throws {
        let context = try TestFactories.inMemoryContext()
        let older = Trip(name: "Older", createdAt: Date(timeIntervalSince1970: 1))
        let newer = Trip(name: "Newer", createdAt: Date(timeIntervalSince1970: 2))
        context.insert(older)
        context.insert(newer)
        try context.save()
        TripStore.setActive(older)

        TripStore.delete(older, in: context)

        XCTAssertEqual(TripStore.activeTripID, newer.id)
        XCTAssertEqual(try fetchTrips(in: context).map(\.name), ["Newer"])
    }

    func testDeletingFinalTripBootstrapsReplacement() throws {
        let context = try TestFactories.inMemoryContext()
        let only = Trip(name: "Only")
        context.insert(only)
        try context.save()
        TripStore.setActive(only)

        TripStore.delete(only, in: context)
        let trips = try fetchTrips(in: context)

        XCTAssertEqual(trips.count, 1)
        XCTAssertNotEqual(trips[0].id, only.id)
        XCTAssertEqual(TripStore.activeTripID, trips[0].id)
    }

    func testRenameIgnoresBlankNamesAndSavesValidNames() throws {
        let context = try TestFactories.inMemoryContext()
        let trip = Trip(name: "Original")
        context.insert(trip)
        try context.save()

        TripStore.rename(trip, to: "   ", in: context)
        XCTAssertEqual(trip.name, "Original")

        TripStore.rename(trip, to: "  Dalton North  ", in: context)
        XCTAssertEqual(trip.name, "Dalton North")
    }

    private func fetchTrips(in context: ModelContext) throws -> [Trip] {
        try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.createdAt)]))
    }
}
