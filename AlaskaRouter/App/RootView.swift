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
    @State private var isSearchFieldFocused: Bool = false

    @State private var mapCamera: MapViewCamera = .center(
        .init(latitude: 63.95, longitude: -148.9), zoom: 8.5
    )

    // Routing layer state
    private let routingProvider: any RoutingProvider = OSRMProvider()
    @State private var networkMonitor = NetworkMonitor()
    @State private var snappedRouteCoords: [CLLocationCoordinate2D]?
    @State private var snappedRouteKey: String = ""        // tracks which trip-state the snap is for
    @State private var snapTask: Task<Void, Never>?
    @State private var pendingSnapKey: String?             // set when fetch failed; retried on reconnect

    private var activeTrip: Trip? { trips.first }

    /// "Search mode active" — field is focused OR there's a non-empty query.
    /// We hide the bottom sheet and dim/hold the map during this state.
    private var isSearchActive: Bool {
        isSearchFieldFocused || !searchService.query.isEmpty
    }

    /// How far above the screen bottom the floating controls should sit, given
    /// the current bottom-sheet detent. Always clears the sheet's collapsed
    /// header; at .overview the sheet is taller so we lift further.
    private var sheetClearance: CGFloat {
        // Disappears entirely when isSearchActive (no sheet shown) — use the
        // collapsed-equivalent clearance so the controls don't jump.
        switch bottomSheetDetent {
        case .collapsed: return 110
        case .overview:  return UIScreen.main.bounds.height * 0.45 + 14
        case .full:      return 0   // unused: controls hidden at .full
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ExpeditionMapView(
                camera: $mapCamera,
                trip: activeTrip,
                selectedWaypointID: selectedWaypointID,
                previewCoord: previewedResult?.coord,
                previewName: previewedResult?.name,
                snappedRouteCoords: snappedRouteCoords
            )
            .ignoresSafeArea()

            // Tap-outside-to-dismiss layer. Only active while searching;
            // intercepts taps that don't hit the bar or the result rows.
            if isSearchActive {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissSearch() }
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                FloatingSearchBar(
                    state: $barState,
                    query: Binding(
                        get: { searchService.query },
                        set: { searchService.setQuery($0) }
                    ),
                    isFieldFocused: $isSearchFieldFocused,
                    activeTripName: activeTrip?.name ?? "(no trip)"
                )
                if barState == .expanded
                    && !searchService.results.isEmpty
                    && previewedResult == nil
                {
                    SearchResultsView(
                        results: searchService.results,
                        parsed: searchService.parsed,
                        onPreview: handlePreviewSelected,
                        onFastAdd: handleFastAdd
                    )
                }
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)

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

            if let trip = activeTrip, !isSearchActive {
                TripBottomSheet(
                    trip: trip,
                    detent: $bottomSheetDetent,
                    onTapWaypoint: handleSheetWaypointTap,
                    onWaypointDeleted: handleSheetWaypointDeleted
                )
                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // On-map controls (right edge, vertical) + scale (bottom-left).
            // Both auto-hide when the sheet is at full detent (covers the map).
            if bottomSheetDetent != .full {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 0) {
                        ScaleIndicator(camera: mapCamera)
                            .padding(.leading, 12)
                            .padding(.bottom, sheetClearance)
                        Spacer()
                        MapControls(camera: $mapCamera)
                            .padding(.trailing, 12)
                            .padding(.bottom, sheetClearance)
                    }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .allowsHitTesting(!isSearchActive)   // don't compete with the search dim layer
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
            networkMonitor.onReconnect = { [self] in
                if let key = pendingSnapKey { fireSnap(forKey: key) }
            }
            scheduleSnapForCurrentTrip()
        }
        .onChange(of: tripGeometryKey) { _, newKey in
            scheduleSnapForCurrentTrip(key: newKey)
        }
    }

    /// A string that changes whenever the snap-relevant trip state changes
    /// (waypoint coordinate sequence). Used as the `.onChange` trigger.
    private var tripGeometryKey: String {
        guard let trip = activeTrip else { return "" }
        return trip.orderedWaypoints
            .map { String(format: "%.5f,%.5f", $0.lat, $0.lon) }
            .joined(separator: "|")
    }

    // MARK: - Routing: debounced snap-to-road fetch

    private func scheduleSnapForCurrentTrip(key: String? = nil) {
        let effectiveKey = key ?? tripGeometryKey
        // Invalidate any prior result that doesn't match the current trip state.
        snapTask?.cancel()
        if snappedRouteKey != effectiveKey { snappedRouteCoords = nil }
        guard let trip = activeTrip, trip.orderedWaypoints.count >= 2 else {
            pendingSnapKey = nil
            return
        }
        let coords = trip.orderedWaypoints.map(\.coordinate)
        snapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)   // 500 ms debounce
            guard !Task.isCancelled else { return }
            await runSnap(coords: coords, key: effectiveKey)
        }
    }

    private func fireSnap(forKey key: String) {
        guard let trip = activeTrip, trip.orderedWaypoints.count >= 2 else { return }
        let coords = trip.orderedWaypoints.map(\.coordinate)
        Task { @MainActor in await runSnap(coords: coords, key: key) }
    }

    @MainActor
    private func runSnap(coords: [CLLocationCoordinate2D], key: String) async {
        do {
            let result = try await routingProvider.snap(waypoints: coords)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.35)) {
                snappedRouteCoords = result.coordinates
                snappedRouteKey = key
                pendingSnapKey = nil
            }
        } catch {
            // Fall back to the dashed pendingSnap line; remember the key so
            // we can retry on reconnect.
            snappedRouteCoords = nil
            pendingSnapKey = key
        }
    }

    // MARK: - Search dismissal

    /// Tap-outside-to-dismiss. Blurs the field and (if query is empty)
    /// collapses the bar to the pill state.
    private func dismissSearch() {
        isSearchFieldFocused = false
        if searchService.query.isEmpty {
            withAnimation(.smooth(duration: 0.25)) { barState = .collapsed }
        }
    }

    // MARK: - Actions: preview (research-first)

    private func handlePreviewSelected(_ result: SearchResult) {
        // Dismiss the keyboard so the user can see the callout + map.
        isSearchFieldFocused = false
        withAnimation(.smooth(duration: 0.45)) {
            previewedResult = result
            mapCamera = .center(result.coord, zoom: zoomForCategory(result.category))
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
        isSearchFieldFocused = false
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
        isSearchFieldFocused = false
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
            previewedResult = nil
            // Leave bottomSheetDetent alone — user keeps control of the sheet's size.
        }
    }

    private func handleSheetWaypointDeleted(_ wp: Waypoint) {
        if selectedWaypointID == wp.id {
            withAnimation(.smooth(duration: 0.2)) { selectedWaypointID = nil }
        }
        if recentlyAddedWaypoint?.id == wp.id {
            withAnimation(.smooth(duration: 0.2)) { recentlyAddedWaypoint = nil }
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
