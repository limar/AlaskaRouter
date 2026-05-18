import SwiftUI

/// The single root screen: a full-screen map with floating chrome on top.
/// v1 architecture — see SPIKE_FINDINGS.md and memory.
struct RootView: View {
    @State private var searchQuery: String = ""
    @State private var barState: FloatingSearchBarState = LaunchArgs.initialBarState

    private let activeTripName: String = "Dalton Highway — North"

    var body: some View {
        ZStack(alignment: .top) {
            ExpeditionMapView()
                .ignoresSafeArea()

            FloatingSearchBar(
                state: $barState,
                query: $searchQuery,
                activeTripName: activeTripName
            )
        }
    }
}
