import SwiftUI
import SwiftData
import MapLibreSwiftUI
import CoreLocation

/// The single root screen: full-screen map + floating chrome + bottom sheet.
struct RootView: View {
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var searchQuery: String = ""
    @State private var barState: FloatingSearchBarState = LaunchArgs.initialBarState
    @State private var searchService = SearchService(db: PlacesDB(bundleResource: "alaska-places"))
    @State private var bottomSheetDetent: TripSheetDetent = LaunchArgs.initialTripDetent

    @State private var mapCamera: MapViewCamera = .center(
        .init(latitude: 63.95, longitude: -148.9), zoom: 8.5
    )

    private var activeTrip: Trip? { trips.first }

    var body: some View {
        ZStack(alignment: .top) {
            ExpeditionMapView(camera: $mapCamera, trip: activeTrip)
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
                        onSelect: handleResultSelected
                    )
                }
                Spacer(minLength: 0)
            }

            if let trip = activeTrip {
                TripBottomSheet(
                    trip: trip,
                    detent: $bottomSheetDetent,
                    onTapWaypoint: flyToWaypoint
                )
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .onAppear {
            if let prefill = LaunchArgs.prefillQuery {
                searchService.setQuery(prefill)
            }
        }
    }

    private func handleResultSelected(_ result: SearchResult) {
        let zoom = zoomForCategory(result.category)
        withAnimation(.smooth(duration: 0.5)) {
            mapCamera = .center(result.coord, zoom: zoom)
            barState = .collapsed
            searchService.setQuery("")
        }
    }

    private func flyToWaypoint(_ wp: Waypoint) {
        withAnimation(.smooth(duration: 0.5)) {
            mapCamera = .center(wp.coordinate, zoom: 12.0)
            bottomSheetDetent = .collapsed
        }
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
