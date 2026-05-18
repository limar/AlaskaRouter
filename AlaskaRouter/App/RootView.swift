import SwiftUI
import MapLibreSwiftUI
import CoreLocation

/// The single root screen: full-screen map with floating chrome on top.
/// v1 architecture — see SPIKE_FINDINGS.md and memory.
struct RootView: View {
    @State private var searchQuery: String = ""
    @State private var barState: FloatingSearchBarState = LaunchArgs.initialBarState
    @State private var searchService = SearchService(db: PlacesDB(bundleResource: "alaska-places"))

    /// Mid-route default; gets overwritten when a search result is tapped.
    @State private var mapCamera: MapViewCamera = .center(
        .init(latitude: 63.95, longitude: -148.9), zoom: 8.5
    )

    private let activeTripName: String = "Dalton Highway — North"

    var body: some View {
        ZStack(alignment: .top) {
            ExpeditionMapView(camera: $mapCamera)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FloatingSearchBar(
                    state: $barState,
                    query: Binding(
                        get: { searchService.query },
                        set: { searchService.setQuery($0) }
                    ),
                    activeTripName: activeTripName
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
        }
        .onAppear {
            if let prefill = LaunchArgs.prefillQuery {
                searchService.setQuery(prefill)
            }
        }
    }

    private func handleResultSelected(_ result: SearchResult) {
        let zoom: Double = zoomForCategory(result.category)
        withAnimation(.smooth(duration: 0.5)) {
            mapCamera = .center(result.coord, zoom: zoom)
            barState = .collapsed
            searchService.setQuery("")          // dismiss results
        }
    }

    private func zoomForCategory(_ category: String) -> Double {
        switch category {
        case "settlement_major":             return 11.5
        case "settlement", "settlement_major", "locality": return 12.5
        case "airfield":                     return 13.0
        case "peak", "glacier", "volcano":   return 11.0
        default:                              return 13.0
        }
    }
}
