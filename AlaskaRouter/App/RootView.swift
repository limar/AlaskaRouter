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
    @State private var recentlyDeletedSnapshot: DeletedStopSnapshot?
    @State private var isSearchFieldFocused: Bool = false
    @State private var showWelcome: Bool = WelcomeFlag.shouldShow
    @State private var sheetMode: SheetMode = LaunchArgs.startInTripsMode ? .trips : .stops
    /// Observed only so SwiftUI re-renders when the active trip changes via
    /// TripStore.setActive. The actual resolution still happens in TripStore.
    @AppStorage("activeTripID") private var activeTripIDObserved: String = ""

    @State private var mapCamera: MapViewCamera = .center(
        .init(latitude: 63.95, longitude: -148.9),
        zoom: LaunchArgs.initialZoom ?? 8.5
    )

    // Routing layer state
    private let routingProvider: any RoutingProvider = OSRMProvider()
    @State private var networkMonitor = NetworkMonitor()
    @State private var locationProvider = LocationProvider()
    /// True between a locate-me tap and the first location fix arriving.
    /// onChange uses this to decide whether to auto-focus on the new fix.
    @State private var pendingLocateMeFocus = false
    @State private var snappedRouteCoords: [CLLocationCoordinate2D]?
    @State private var snappedRouteKey: String = ""        // tracks which trip-state the snap is for
    @State private var snapTask: Task<Void, Never>?
    @State private var pendingSnapKey: String?             // set when fetch failed; retried on reconnect

    private var activeTrip: Trip? { TripStore.resolveActive(from: trips) }

    /// "Search mode active" — field is focused OR there's a non-empty query.
    /// We hide the bottom sheet and dim/hold the map during this state.
    private var isSearchActive: Bool {
        isSearchFieldFocused || !searchService.query.isEmpty
    }

    /// Fixed clearance above the screen bottom for on-map controls + scale.
    /// Anchored — the sheet expanding ABOVE them is fine; chasing the sheet
    /// produced a "running cockroach" miss-click problem (AlaskaRouter-ir85).
    /// Cleared above the .collapsed sheet header so the controls remain
    /// reachable in the user's primary "map mode" interaction state.
    private let mapControlsBottomClearance: CGFloat = 110

    var body: some View {
        ZStack(alignment: .top) {
            ExpeditionMapView(
                camera: $mapCamera,
                trip: activeTrip,
                selectedWaypointID: selectedWaypointID,
                previewCoord: previewedResult?.coord,
                previewName: previewedResult?.name,
                snappedRouteCoords: snappedRouteCoords,
                userLocation: locationProvider.lastLocation?.coordinate,
                onWaypointTap: handleMapWaypointTap
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

            // Stop callout — shown when a trip waypoint is selected, the user
            // isn't previewing a search result, and search isn't active.
            if previewedResult == nil, !isSearchActive,
               let trip = activeTrip,
               let selectedID = selectedWaypointID,
               let wp = trip.orderedWaypoints.first(where: { $0.id == selectedID })
            {
                let ordered = trip.orderedWaypoints
                let idx = ordered.firstIndex { $0.id == selectedID } ?? 0
                VStack {
                    Spacer()
                    StopCallout(
                        waypoint: wp,
                        positionLabel: "STOP \(idx + 1) OF \(ordered.count)",
                        distanceFromPrevText: distanceFromPrevText(idx: idx, in: ordered),
                        canPrev: idx > 0,
                        canNext: idx < ordered.count - 1,
                        onPrev: { handleStopCalloutPrev(in: ordered, currentIdx: idx) },
                        onNext: { handleStopCalloutNext(in: ordered, currentIdx: idx) },
                        onClose: { handleStopCalloutClose() },
                        onRemove: { handleStopCalloutRemove(wp) }
                    )
                    .padding(.horizontal, 18)
                    Spacer()
                    Spacer()
                }
                .allowsHitTesting(true)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            // On-map controls (right edge, vertical) + scale (bottom-left).
            // Pinned to a fixed bottom clearance, rendered BEFORE the sheet
            // so the sheet covers them when it expands above .collapsed.
            // (ir85: anchor them, let the sheet cover them — no chasing.)
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    ScaleIndicator(camera: mapCamera)
                        .padding(.leading, 12)
                        .padding(.bottom, mapControlsBottomClearance)
                    Spacer()
                    MapControls(camera: $mapCamera, onLocateMe: handleLocateMe)
                        .padding(.trailing, 12)
                        .padding(.bottom, mapControlsBottomClearance)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .allowsHitTesting(!isSearchActive)   // don't compete with the search dim layer

            if let trip = activeTrip, !isSearchActive {
                TripBottomSheet(
                    trip: trip,
                    detent: $bottomSheetDetent,
                    mode: $sheetMode,
                    onTapWaypoint: handleSheetWaypointTap,
                    onWaypointDeleted: handleSheetWaypointDeleted
                )
                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let added = recentlyAddedWaypoint {
                VStack {
                    Spacer()
                    TripEditToast(
                        kind: .added,
                        waypointLabel: added.label ?? "(stop)",
                        onUndo: { undoAdd(added) }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)   // sits above the bottom sheet
                }
                .id(added.id)
            } else if let deleted = recentlyDeletedSnapshot {
                VStack {
                    Spacer()
                    TripEditToast(
                        kind: .removed,
                        waypointLabel: deleted.label ?? "(stop)",
                        onUndo: { undoDelete(deleted) }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)
                }
                .id(deleted.id)
            }

            // First-launch welcome card — once-only, gated by UserDefaults.
            if showWelcome {
                WelcomeOverlay(onDismiss: dismissWelcome)
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
            if LaunchArgs.autoLocateMe {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    handleLocateMe()
                }
            }
            if LaunchArgs.preloadDemoRoute, snappedRouteCoords == nil {
                if let url = Bundle.main.url(forResource: "demo-route", withExtension: "geojson"),
                   let data = try? Data(contentsOf: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let feats = json["features"] as? [[String: Any]],
                   let geom = feats.first?["geometry"] as? [String: Any],
                   let coords = geom["coordinates"] as? [[Double]] {
                    snappedRouteCoords = coords.compactMap {
                        guard $0.count >= 2 else { return nil }
                        return CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
                    }
                }
            }
            if let idx = LaunchArgs.preselectStopIndex {
                // Race with SwiftData @Query — on a fresh install the just-seeded
                // trip may not have propagated to `trips` when onAppear runs.
                // Defer the preselect a couple frames so activeTrip is ready.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard let trip = activeTrip,
                          idx >= 0, idx < trip.orderedWaypoints.count else { return }
                    let wp = trip.orderedWaypoints[idx]
                    withAnimation(.smooth(duration: 0.2)) {
                        if !LaunchArgs.cameraOnlyNoSelect {
                            selectedWaypointID = wp.id
                        }
                        mapCamera = .center(wp.coordinate, zoom: LaunchArgs.initialZoom ?? 8.5)
                    }
                }
            }
        }
        .onChange(of: tripGeometryKey) { _, newKey in
            scheduleSnapForCurrentTrip(key: newKey)
        }
        // First location fix after a locate-me tap → focus the camera.
        // (We don't use MapLibreSwiftUI's tracking mode for showsUserLocation
        // anymore — the blue puck is rendered as our own SymbolStyleLayer,
        // see WaypointIcons.userLocation. That keeps the dot rendering
        // reliable regardless of the wrapper's tracking semantics.)
        .onChange(of: locationProvider.lastLocation) { _, new in
            guard pendingLocateMeFocus, let new else { return }
            focusOnUserLocation(new.coordinate)
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
        searchService.setQuery("")
        isSearchFieldFocused = false
        withAnimation(.smooth(duration: 0.25)) { barState = .collapsed }
    }

    private func dismissWelcome() {
        WelcomeFlag.markSeen()
        withAnimation(.easeOut(duration: 0.25)) { showWelcome = false }
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
            sheetMode = .stops
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
            // Force the sheet back to the stops list so the user sees their
            // newly-added stop instead of the trip switcher.
            sheetMode = .stops
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
        // Preserve the user's chosen zoom level — they're navigating between
        // their own stops, not exploring a new place at an "appropriate" scale.
        // See AlaskaRouter-q8nl. Same pattern as locate-me (j03u).
        withAnimation(.smooth(duration: 0.5)) {
            mapCamera = .center(wp.coordinate, zoom: currentMapZoom())
            selectedWaypointID = wp.id
            previewedResult = nil
            // Leave bottomSheetDetent alone — user keeps control of the sheet's size.
        }
    }

    // MARK: - Locate me (AlaskaRouter-j03u)

    private func handleLocateMe() {
        switch locationProvider.authorizationStatus {
        case .notDetermined:
            // First tap → request permission. The delegate will start updates
            // when the user grants; the next tap will then focus.
            locationProvider.requestWhenInUse()
        case .restricted, .denied:
            // Could surface a Settings deep-link here. For v1 we silently
            // no-op; the user can grant via Settings and retry.
            return
        case .authorizedWhenInUse, .authorizedAlways:
            locationProvider.startUpdating()
            pendingLocateMeFocus = true
            // If we already have a fix, focus immediately. Otherwise the
            // .onChange below will fire when the first one arrives.
            if let loc = locationProvider.lastLocation {
                focusOnUserLocation(loc.coordinate)
            }
        @unknown default:
            return
        }
    }

    private func focusOnUserLocation(_ coord: CLLocationCoordinate2D) {
        let z = currentMapZoom()
        withAnimation(.smooth(duration: 0.4)) {
            mapCamera = .center(coord, zoom: z)
        }
        pendingLocateMeFocus = false
    }

    /// Current camera zoom regardless of camera mode. Used so locate-me
    /// preserves zoom whether we're already centered or tracking.
    private func currentMapZoom() -> Double {
        switch mapCamera.state {
        case let .centered(_, zoom, _, _, _):                              return zoom
        case let .trackingUserLocation(zoom, _, _, _):                     return zoom
        case let .trackingUserLocationWithHeading(zoom, _, _):             return zoom
        case let .trackingUserLocationWithCourse(zoom, _, _):              return zoom
        default:                                                            return 12.0
        }
    }

    // MARK: - Stop callout (AlaskaRouter-kcq8)

    private func handleMapWaypointTap(_ id: UUID?) {
        guard let id else {
            // Empty area tap — dismiss any selection / callout.
            withAnimation(.smooth(duration: 0.2)) { selectedWaypointID = nil }
            return
        }
        guard let trip = activeTrip,
              let wp = trip.orderedWaypoints.first(where: { $0.id == id })
        else { return }
        // Preserve the user's chosen zoom (q8nl).
        withAnimation(.smooth(duration: 0.2)) {
            selectedWaypointID = wp.id
            mapCamera = .center(wp.coordinate, zoom: currentMapZoom())
        }
    }

    private func handleStopCalloutClose() {
        withAnimation(.smooth(duration: 0.2)) { selectedWaypointID = nil }
    }

    private func handleStopCalloutPrev(in ordered: [Waypoint], currentIdx: Int) {
        guard currentIdx > 0 else { return }
        let wp = ordered[currentIdx - 1]
        // Preserve the user's chosen zoom — walking Prev/Next is a "scan my
        // route at this scale" gesture, not a "fly me to each stop" gesture (q8nl).
        withAnimation(.smooth(duration: 0.25)) {
            selectedWaypointID = wp.id
            mapCamera = .center(wp.coordinate, zoom: currentMapZoom())
        }
    }

    private func handleStopCalloutNext(in ordered: [Waypoint], currentIdx: Int) {
        guard currentIdx < ordered.count - 1 else { return }
        let wp = ordered[currentIdx + 1]
        // Preserve the user's chosen zoom (q8nl).
        withAnimation(.smooth(duration: 0.25)) {
            selectedWaypointID = wp.id
            mapCamera = .center(wp.coordinate, zoom: currentMapZoom())
        }
    }

    /// Callout's destructive primary action. Per user spec for kcq8: instant
    /// delete, no Undo toast, no confirmation alert. (Different from the
    /// sheet trash, which DOES get an Undo toast.)
    private func handleStopCalloutRemove(_ wp: Waypoint) {
        let id = wp.id
        modelContext.delete(wp)
        // Renumber remaining stops to keep .order contiguous.
        if let trip = activeTrip {
            let remaining = trip.orderedWaypoints
            for (i, w) in remaining.enumerated() { w.order = i }
        }
        try? modelContext.save()
        withAnimation(.smooth(duration: 0.2)) {
            if selectedWaypointID == id { selectedWaypointID = nil }
            if recentlyAddedWaypoint?.id == id { recentlyAddedWaypoint = nil }
        }
    }

    /// Straight-line distance to the previous stop, formatted as "45 km".
    /// Returns nil for stop 0 (no previous).
    private func distanceFromPrevText(idx: Int, in ordered: [Waypoint]) -> String? {
        guard idx > 0, idx < ordered.count else { return nil }
        let a = ordered[idx - 1].coordinate
        let b = ordered[idx].coordinate
        let meters = SmartInsert.haversine(a, b)
        return String(format: "%.0f km from previous", meters / 1000)
    }

    private func handleSheetWaypointDeleted(_ snapshot: DeletedStopSnapshot) {
        if selectedWaypointID == snapshot.id {
            withAnimation(.smooth(duration: 0.2)) { selectedWaypointID = nil }
        }
        if recentlyAddedWaypoint?.id == snapshot.id {
            withAnimation(.smooth(duration: 0.2)) { recentlyAddedWaypoint = nil }
        }
        // Show the Undo toast and schedule auto-dismiss.
        withAnimation(.smooth(duration: 0.2)) {
            recentlyDeletedSnapshot = snapshot
        }
        scheduleDeletedToastDismiss(snapshotID: snapshot.id)
    }

    private func scheduleDeletedToastDismiss(snapshotID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if recentlyDeletedSnapshot?.id == snapshotID {
                withAnimation(.smooth(duration: 0.25)) { recentlyDeletedSnapshot = nil }
            }
        }
    }

    private func undoDelete(_ snapshot: DeletedStopSnapshot) {
        guard let trip = activeTrip else { return }
        // Re-insert at the original order, shifting subsequent stops up.
        let restored = Waypoint(
            order: snapshot.order,
            coordinate: snapshot.coordinate,
            label: snapshot.label,
            category: snapshot.category
        )
        restored.trip = trip
        modelContext.insert(restored)
        for wp in trip.orderedWaypoints where wp.id != restored.id && wp.order >= snapshot.order {
            wp.order += 1
        }
        try? modelContext.save()
        withAnimation(.smooth(duration: 0.25)) {
            recentlyDeletedSnapshot = nil
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
