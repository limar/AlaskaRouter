import SwiftUI
import SwiftData
import MapLibreSwiftUI
import CoreLocation

/// The single root screen: full-screen map + floating chrome + bottom sheet.
/// Search → add-to-trip supports two flows:
///   A) Research-first — tap result row body → preview pin + floating callout.
///                       User decides; on "Add to trip" they commit.
///   B) Fast add — tap the "+" button on a result row → instant geographic-smart
///                  insert, brief toast with Undo.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var searchQuery: String = ""
    @State private var barState: FloatingSearchBarState = LaunchArgs.initialBarState
    @State private var searchService = SearchService(db: PlacesDB(bundleResource: "alaska-places"))
    @State private var bottomSheetDetent: TripSheetDetent = LaunchArgs.initialTripDetent

    @State private var selectedWaypointID: UUID?
    @State private var previewedResult: SearchResult?
    @State private var recentlyAddedWaypoint: Waypoint?

    @State private var mapCamera: MapViewCamera = .center(
        .init(latitude: 63.95, longitude: -148.9), zoom: 8.5
    )

    private var activeTrip: Trip? { trips.first }

    var body: some View {
        ZStack(alignment: .top) {
            ExpeditionMapView(
                camera: $mapCamera,
                trip: activeTrip,
                selectedWaypointID: selectedWaypointID,
                previewCoord: previewedResult?.coord,
                previewName: previewedResult?.name
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                FloatingSearchBar(
                    state: $barState,
                    query: Binding(
                        get: { searchService.query },
                        set: { searchService.setQuery($0) }
                    ),
                    activeTripName: activeTrip?.name ?? "(no trip)"
                )
                if barState == .expanded && !searchService.results.isEmpty {
                    SearchResultsView(
                        results: searchService.results,
                        parsed: searchService.parsed,
                        onPreview: handlePreviewSelected,
                        onFastAdd: handleFastAdd
                    )
                }
                Spacer(minLength: 0)
            }

            // Preview callout (floating mid-screen near the previewed pin).
            if let preview = previewedResult {
                VStack {
                    Spacer()
                    PreviewCallout(
                        result: preview,
                        distanceFromTripText: distanceLineFromTrip(to: preview.coord),
                        onAdd: { handleAddPreviewed(preview) },
                        onDismiss: { dismissPreview() }
                    )
                    .padding(.horizontal, 18)
                    Spacer()
                    Spacer()        // keep callout in upper 1/3 area
                }
                .allowsHitTesting(true)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }

            if let trip = activeTrip {
                TripBottomSheet(
                    trip: trip,
                    detent: $bottomSheetDetent,
                    onTapWaypoint: handleSheetWaypointTap
                )
                .ignoresSafeArea(.container, edges: .bottom)
            }

            if let added = recentlyAddedWaypoint {
                VStack {
                    Spacer()
                    AddedToTripToast(
                        waypointLabel: added.label ?? "(stop)",
                        onUndo: { undoAdd(added) }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)   // sits above the bottom sheet
                }
                .id(added.id)
            }
        }
        .onAppear {
            if let prefill = LaunchArgs.prefillQuery {
                searchService.setQuery(prefill)
                if let action = LaunchArgs.debugAutoAction {
                    // Wait for the FTS5 query + debounce to land, then fire the action.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        let idx = action.index
                        guard idx < searchService.results.count else { return }
                        let target = searchService.results[idx]
                        switch action.kind {
                        case "preview": handlePreviewSelected(target)
                        case "add":     handleFastAdd(target)
                        default:        break
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions: preview (research-first)

    private func handlePreviewSelected(_ result: SearchResult) {
        withAnimation(.smooth(duration: 0.45)) {
            previewedResult = result
            mapCamera = .center(result.coord, zoom: zoomForCategory(result.category))
            // Keep search bar expanded behind callout so user can scan other results easily.
            // Selection isn't applied here — the result isn't committed yet.
            selectedWaypointID = nil
        }
    }

    private func handleAddPreviewed(_ result: SearchResult) {
        guard let trip = activeTrip else { return }
        let new = SmartInsert.insertSmart(
            coordinate: result.coord,
            label: result.name,
            category: result.category,
            into: trip,
            using: modelContext
        )
        withAnimation(.smooth(duration: 0.45)) {
            previewedResult = nil
            barState = .collapsed
            searchService.setQuery("")
            selectedWaypointID = new.id
            bottomSheetDetent = .overview
            recentlyAddedWaypoint = new
            mapCamera = .center(new.coordinate, zoom: zoomForCategory(result.category))
        }
        scheduleToastDismiss(waypointID: new.id)
    }

    private func dismissPreview() {
        withAnimation(.smooth(duration: 0.25)) { previewedResult = nil }
    }

    // MARK: - Actions: fast add ("+" button)

    private func handleFastAdd(_ result: SearchResult) {
        guard let trip = activeTrip else { return }
        let new = SmartInsert.insertSmart(
            coordinate: result.coord,
            label: result.name,
            category: result.category,
            into: trip,
            using: modelContext
        )
        withAnimation(.smooth(duration: 0.45)) {
            barState = .collapsed
            searchService.setQuery("")
            selectedWaypointID = new.id
            bottomSheetDetent = .overview
            recentlyAddedWaypoint = new
            mapCamera = .center(new.coordinate, zoom: zoomForCategory(result.category))
        }
        scheduleToastDismiss(waypointID: new.id)
    }

    private func scheduleToastDismiss(waypointID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if recentlyAddedWaypoint?.id == waypointID {
                withAnimation(.smooth(duration: 0.25)) { recentlyAddedWaypoint = nil }
            }
        }
    }

    private func undoAdd(_ waypoint: Waypoint) {
        let wasSelected = selectedWaypointID == waypoint.id
        modelContext.delete(waypoint)
        try? modelContext.save()
        withAnimation(.smooth(duration: 0.25)) {
            recentlyAddedWaypoint = nil
            if wasSelected { selectedWaypointID = nil }
        }
    }

    // MARK: - Bottom sheet tap

    private func handleSheetWaypointTap(_ wp: Waypoint) {
        withAnimation(.smooth(duration: 0.5)) {
            mapCamera = .center(wp.coordinate, zoom: 12.0)
            selectedWaypointID = wp.id
            bottomSheetDetent = .collapsed
            previewedResult = nil
        }
    }

    // MARK: - Helpers

    private func distanceLineFromTrip(to coord: CLLocationCoordinate2D) -> String? {
        guard let trip = activeTrip, !trip.waypoints.isEmpty else { return nil }
        var nearest: (Waypoint, Double)? = nil
        for wp in trip.orderedWaypoints {
            let d = SmartInsert.haversine(coord, wp.coordinate)
            if nearest == nil || d < nearest!.1 { nearest = (wp, d) }
        }
        guard let (wp, meters) = nearest else { return nil }
        let km = meters / 1000
        return String(format: "%.0f km from %@", km, wp.label ?? "the route")
    }

    private func zoomForCategory(_ category: String) -> Double {
        switch category {
        case "settlement_major":             return 11.5
        case "settlement", "locality":       return 12.5
        case "airfield":                     return 13.0
        case "peak", "glacier", "volcano":   return 11.0
        default:                             return 13.0
        }
    }
}
