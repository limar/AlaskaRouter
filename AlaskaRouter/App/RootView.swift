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
    @Environment(\.scenePhase) private var scenePhase
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
    /// In-app live design tweaks (AlaskaRouter-ykuf). Observed here so a
    /// tweak change re-renders body, propagating through to ExpeditionMapView
    /// where the unsafe hook reads the latest values for the next frame.
    @State private var tweaksStore = TweaksStore.shared
    @State private var showTweaksPanel: Bool = false
    /// Observed only so SwiftUI re-renders when the active trip changes via
    /// TripStore.setActive. The actual resolution still happens in TripStore.
    @AppStorage("activeTripID") private var activeTripIDObserved: String = ""

    @State private var mapCamera: MapViewCamera = RootView.makeInitialCamera()

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


    private var activeTrip: Trip? {
        // Read activeTripIDObserved here so SwiftUI tracks the @AppStorage
        // dependency — TripStore.setActive writes UserDefaults["activeTripID"]
        // directly (bypassing the wrapper), and without an in-body access of
        // the wrapper SwiftUI wouldn't notice and the trip wouldn't switch.
        _ = activeTripIDObserved
        return TripStore.resolveActive(from: trips)
    }

    /// Computed string read from the @Observable TweaksStore. Body reading
    /// this property gives SwiftUI a dependency edge so any tweak change
    /// triggers a re-render → ExpeditionMapView's unsafe hook fires →
    /// markers re-rendered with the new tweak values.
    private var tweaksFingerprint: String {
        String(
            format: "d%.0f-s%.0f-w%.2f-r%.2f-m%d-L%.2f",
            tweaksStore.dotDiameterDefault,
            tweaksStore.dotDiameterSelected,
            tweaksStore.dotFontWeight,
            tweaksStore.dotFontSizeRatio,
            tweaksStore.placeMarkerStyle,       // vyfe spike — re-register place icons on change
            tweaksStore.labelSizeMultiplier     // vyfe iter 7 — apply label-size scaling on change
        )
    }

    /// Live-design tweaks trigger. Styled as map chrome, same footprint as
    /// zoom / locate controls, and rendered in the map-control Z layer.
    private var tweaksTriggerButton: some View {
        Button {
            showTweaksPanel = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

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
                tweaksFingerprint: tweaksFingerprint,
                onWaypointTap: handleMapWaypointTap,
                onPlaceTap: handleMapPlaceTap,
                onEmptyMapTap: handleMapEmptyTap
            )
            .ignoresSafeArea()

            // (y7l0) Search-mode scrim. When search is active (field focused
            // OR there's a non-empty query), this transparent layer sits
            // above the map and below the bar/results. ANY touch on it
            // dismisses search and goes nowhere else — per the user's
            // explicit spec: "Any touch on map (tap, drag, pinch, whatever)
            // should just dismiss the search sheet without doing anything
            // else." A DragGesture with minimumDistance: 0 catches the
            // touch-down phase of every gesture (tap, pan, the start of a
            // pinch), so we don't need separate Magnify/Rotate handlers.
            //
            // Unlike the old dim-layer from before eai0/l556 (which was
            // removed because it ate gestures with no behavior), this scrim
            // INTENTIONALLY eats gestures and triggers `dismissSearch()` for
            // each — restoring the "tap-outside-to-dismiss" intent but for
            // all gesture types, not just taps.
            if isSearchActive {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in dismissSearch() }
                    )
                    .onTapGesture { dismissSearch() }
            }

            // On-map controls (right edge, vertical) + scale (bottom-left)
            // + tweaks trigger (top-right). All live in this early ZStack
            // layer so search/results and sheets cover them like map chrome.
            // Pinned to a fixed bottom clearance, rendered BEFORE the bar/
            // results VStack and the bottom sheet so both cover the controls
            // visually when they overlap. (qat6: previously the controls
            // floated above a long search-results sheet — moved them earlier
            // in the ZStack so they "stick to the map.") (ir85 still holds:
            // anchor them, let the sheet cover them — no chasing.)
            VStack {
                HStack {
                    Spacer()
                    tweaksTriggerButton
                        .padding(.trailing, 12)
                        .padding(.top, 72)   // clears the expanded search bar
                }
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
            .allowsHitTesting(!isSearchActive)   // taps pass through to scrim when search is active

            VStack(spacing: 0) {
                FloatingSearchBar(
                    state: $barState,
                    query: Binding(
                        get: { searchService.query },
                        set: { searchService.setQuery($0) }
                    ),
                    isFieldFocused: $isSearchFieldFocused,
                    activeTripName: activeTrip?.name ?? "(no trip)",
                    onCancel: dismissSearch
                )
                if barState == .expanded
                    && !searchService.results.isEmpty
                    && previewedResult == nil
                {
                    // Restored ab23a70's layout: a plain ScrollView that
                    // scrolls internally when content overflows. The bar
                    // stays put (it's earlier in the VStack and has its
                    // intrinsic height). No artificial cap — the user sees
                    // every match. Dismissal is handled by the y7l0 Cancel
                    // button (always available when focused) and the
                    // map-touch scrim (any gesture on visible map → dismiss).
                    ScrollView {
                        SearchResultsView(
                            results: searchService.results,
                            parsed: searchService.parsed,
                            onPreview: handlePreviewSelected,
                            onFastAdd: handleFastAdd
                        )
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                Spacer(minLength: 0)
            }
            // Deliberately NOT .ignoresSafeArea(.keyboard, edges: .bottom):
            // we WANT SwiftUI's standard keyboard avoidance to shrink the
            // VStack from the bottom when the keyboard appears. The bar
            // (top of VStack) stays visible since the top is unaffected.

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
                        additionalPassNumbers: additionalPassNumbers(for: wp, in: ordered),
                        distanceFromPrevText: distanceFromPrevText(idx: idx, in: ordered),
                        distanceToNextText: distanceToNextText(idx: idx, in: ordered),
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

            if let trip = activeTrip, !isSearchActive {
                TripBottomSheet(
                    trip: trip,
                    detent: $bottomSheetDetent,
                    mode: $sheetMode,
                    snappedRouteCoords: snappedRouteCoords,
                    onTapWaypoint: handleSheetWaypointTap,
                    onWaypointDeleted: handleSheetWaypointDeleted
                )
                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Add/Removed toasts dropped (AlaskaRouter-upw4): the newly-added
            // row appearing in the list (and swipe-to-delete being the explicit
            // gesture) is feedback enough; the toast was noise on top. The
            // underlying state (recentlyAddedWaypoint, recentlyDeletedSnapshot)
            // is kept so a different feedback channel (haptic, shake-to-undo,
            // ⌘Z) can be wired up later without rewiring the mutation paths.

            // First-launch welcome card — once-only, gated by UserDefaults.
            if showWelcome {
                WelcomeOverlay(onDismiss: dismissWelcome)
            }
        }
        .sheet(isPresented: $showTweaksPanel) {
            TweaksPanel(tweaks: tweaksStore)
                // (xvb8) Full-screen by default — the panel has grown enough
                // that .medium forced scrolling for the bottom sections.
                .presentationDetents([.large])
        }
        .onAppear {
            // (4r8l) Pre-parse places.geojson into the AdminAreaLookup
            // donor table so the first empty-map tap doesn't pay the
            // ~200 ms parse cost. Idempotent; subsequent calls no-op.
            AdminAreaLookup.shared.startLoad()

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
        .onChange(of: scenePhase) { _, newPhase in
            // Save the current view when leaving the foreground so the next
            // launch reopens where the user was (AlaskaRouter-2ufd).
            if newPhase != .active { persistLastMapView() }
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

        // (kp9h) Try the persisted cache first. If the trip has a stored snap
        // computed for the *same* geometry key, hydrate immediately — even if
        // we're offline. This is the whole point of the persistence: a trip
        // routed yesterday over LTE still renders along real roads at 5 AM
        // out of Coldfoot when the bars are gone.
        if let cached = trip.cachedSnappedCoords(for: effectiveKey) {
            snappedRouteCoords = cached
            snappedRouteKey = effectiveKey
            pendingSnapKey = nil
            return                          // no refetch needed
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
            // (kp9h) Persist for offline reopen. If the trip's geometry has
            // changed during the in-flight network call (a fast user edit),
            // the key won't match by now — skip the save so we don't write a
            // stale snap.
            if let trip = activeTrip, tripGeometryKey == key {
                trip.setSnappedCoords(result.coordinates, geometryKey: key)
                try? modelContext.save()
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
            bottomSheetDetent = .overview
            sheetMode = .stops
            mapCamera = .center(new.coordinate, zoom: zoomForCategory(result.category))
            // wqt4: declutter — the user's tap is the action, the marker on
            // the map + the new row in the sheet are the confirmation. We
            // intentionally do NOT auto-select the new waypoint (avoids
            // popping the StopCallout) and do NOT emit the "Added · Undo"
            // toast (the action is reversible via the sheet's trash button).
            // Will revisit when the selection visual is reworked into
            // something easy on the eye.
            _ = new
        }
    }

    private func dismissPreview() {
        withAnimation(.smooth(duration: 0.25)) { previewedResult = nil }
    }

    // MARK: - Actions: fast add ("+" button)

    private func handleFastAdd(_ result: SearchResult) {
        guard let trip = activeTrip else { return }
        // 65hf: fast-add appends to the end; the user is enumerating stops in
        // the order they'll drive them. Preview-add (handleAddPreviewed) keeps
        // SmartInsert because it's a deliberate one-result-at-a-time flow.
        let new = SmartInsert.appendOnly(
            coordinate: result.coord,
            label: result.name,
            category: result.category,
            into: trip,
            using: modelContext
        )
        // gxv0: keep search open for the "type, +, type, +" rapid-add
        // workflow. The user stays focused on the search field; only the
        // QUERY clears so they can type the next term immediately. Camera
        // still pans to each newly-added waypoint as visual confirmation;
        // sheet flips to stops mode so the new stops are visible when the
        // user eventually dismisses search.
        withAnimation(.smooth(duration: 0.45)) {
            searchService.setQuery("")
            bottomSheetDetent = .overview
            sheetMode = .stops
            mapCamera = .center(new.coordinate, zoom: zoomForCategory(result.category))
            // wqt4: still no auto-select, no toast.
            _ = new
        }
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

    // MARK: - Last-view persistence (AlaskaRouter-2ufd)

    private static let lastCenterLatKey = "lastMapCenterLat"
    private static let lastCenterLonKey = "lastMapCenterLon"
    private static let lastZoomKey = "lastMapZoom"

    /// Default Alaska framing used on a fresh install (no saved view yet).
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 63.95, longitude: -148.9)
    private static let defaultZoom = 8.5

    /// Seed the camera from the last view the user left the app on, so the map
    /// opens where they were rather than at a fixed point far from the route.
    /// Skipped when `initialZoom` is set so screenshot / UI-test launches stay
    /// deterministic; falls back to the Alaska default when nothing is saved.
    private static func makeInitialCamera() -> MapViewCamera {
        let d = UserDefaults.standard
        if LaunchArgs.initialZoom == nil, d.object(forKey: lastZoomKey) != nil {
            let center = CLLocationCoordinate2D(
                latitude: d.double(forKey: lastCenterLatKey),
                longitude: d.double(forKey: lastCenterLonKey)
            )
            let zoom = d.double(forKey: lastZoomKey)
            if CLLocationCoordinate2DIsValid(center), zoom > 0 {
                return .center(center, zoom: zoom)
            }
        }
        return .center(defaultCenter, zoom: LaunchArgs.initialZoom ?? defaultZoom)
    }

    /// Persist the current map center + zoom so the next launch restores it.
    /// Only the `.centered` state carries an explicit coordinate; tracking
    /// states (locate-me) are skipped, leaving the last explicit view saved.
    private func persistLastMapView() {
        guard case let .centered(center, zoom, _, _, _) = mapCamera.state else { return }
        let d = UserDefaults.standard
        d.set(center.latitude, forKey: Self.lastCenterLatKey)
        d.set(center.longitude, forKey: Self.lastCenterLonKey)
        d.set(zoom, forKey: Self.lastZoomKey)
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

    private func handleMapWaypointTap(_ id: UUID) {
        // (l556 / eai0) If search is active, a tap on the map dismisses
        // search. The map's native single-tap recognizer fires this for
        // a hit on one of the trip-waypoint marker layers; empty taps
        // now go through `handleMapEmptyTap` (4r8l) instead, so we no
        // longer need the `nil` id branch here.
        if isSearchActive { dismissSearch() }
        guard let trip = activeTrip,
              let wp = trip.orderedWaypoints.first(where: { $0.id == id })
        else { return }
        // Preserve the user's chosen zoom (q8nl).
        withAnimation(.smooth(duration: 0.2)) {
            selectedWaypointID = wp.id
            mapCamera = .center(wp.coordinate, zoom: currentMapZoom())
        }
    }

    /// AlaskaRouter-4r8l — empty-area tap. iOS Maps convention: tap
    /// dismisses any open overlay first; a second tap on truly empty
    /// terrain drops a pin. We render the pin as a synthesized "Dropped
    /// pin" SearchResult so the existing PreviewCallout renders with
    /// "+ Add to trip" and we reuse the same SmartInsert add path.
    /// Admin area is resolved at runtime via nearest-GNIS-within-30 km.
    private func handleMapEmptyTap(_ coord: CLLocationCoordinate2D) {
        // Dismiss-first behavior (highest priority each).
        if isSearchActive {
            dismissSearch()
            return
        }
        if previewedResult != nil {
            withAnimation(.smooth(duration: 0.2)) { previewedResult = nil }
            return
        }
        if selectedWaypointID != nil {
            withAnimation(.smooth(duration: 0.2)) { selectedWaypointID = nil }
            return
        }
        // Truly empty — drop a pin.
        let admin = AdminAreaLookup.shared.nearestAdmin(for: coord)
        var hasher = Hasher()
        hasher.combine(coord.latitude)
        hasher.combine(coord.longitude)
        let synthId = Int64(hasher.finalize())
        let pin = SearchResult(
            id: synthId,
            name: "Dropped pin",
            altNames: "",
            category: "",                                  // default mappin.circle.fill
            coord: coord,
            importance: 0,
            stage: SearchStage.strict.rawValue,
            editDistance: 0,
            adminArea: admin
        )
        withAnimation(.smooth(duration: 0.2)) {
            previewedResult = pin
        }
    }

    /// AlaskaRouter-5gmw — handle a tap on a places.geojson feature.
    /// We synthesize a `SearchResult` from the map-tap data and route it
    /// through the existing `previewedResult` state, which then makes the
    /// already-built `PreviewCallout` render with "+ Add to trip". Same
    /// add path as search-result preview — `handleAddPreviewed` does the
    /// SmartInsert.
    private func handleMapPlaceTap(_ tap: MapPlaceTap) {
        // Dismiss search if it was active — the user is interacting with
        // the map, not the search.
        if isSearchActive { dismissSearch() }
        // Deterministic id so SwiftUI diffs cleanly when consecutive taps
        // hit different places. id space is disjoint from search-result
        // rowids (which are positive ints < ~50k); using the hash here
        // can't collide in practice.
        var hasher = Hasher()
        hasher.combine(tap.name)
        hasher.combine(tap.coord.latitude)
        hasher.combine(tap.coord.longitude)
        let synthId = Int64(hasher.finalize())

        let result = SearchResult(
            id: synthId,
            name: tap.name,
            altNames: "",
            category: tap.category,
            coord: tap.coord,
            importance: 0,
            stage: SearchStage.strict.rawValue,
            editDistance: 0,
            adminArea: tap.adminArea
        )
        withAnimation(.smooth(duration: 0.2)) {
            // Replaces any previous preview (from search OR from another
            // map tap) — only one preview at a time.
            previewedResult = result
            // Clear any selected trip waypoint so the StopCallout doesn't
            // also show.
            selectedWaypointID = nil
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

    /// Road distance to the previous stop (along the snapped polyline; falls
    /// back to straight-line haversine when offline / unrouted). Uses the same
    /// Trip.legDistancesMeters source as the bottom sheet so the two surfaces
    /// agree (AlaskaRouter-wrso bug).
    private func distanceFromPrevText(idx: Int, in ordered: [Waypoint]) -> String? {
        guard idx > 0, idx < ordered.count else { return nil }
        let meters = legMeters(legIndex: idx - 1, in: ordered)
        let name = ordered[idx - 1].label ?? "previous"
        return "\(DistanceFormat.string(meters: meters, useMiles: tweaksStore.distanceUnitIsMiles)) from \(name)"
    }

    /// Road distance to the next stop (snapped, with straight-line fallback).
    /// Returns nil for the last stop. See `distanceFromPrevText` for the source.
    private func distanceToNextText(idx: Int, in ordered: [Waypoint]) -> String? {
        guard idx >= 0, idx + 1 < ordered.count else { return nil }
        let meters = legMeters(legIndex: idx, in: ordered)
        let name = ordered[idx + 1].label ?? "next"
        return "\(DistanceFormat.string(meters: meters, useMiles: tweaksStore.distanceUnitIsMiles)) to \(name)"
    }

    /// Metres for leg `legIndex` (ordered[legIndex] → ordered[legIndex+1]).
    /// Mirrors the bottom sheet's source so distances are consistent across
    /// surfaces: road via the snapped polyline when available, straight-line
    /// haversine otherwise.
    private func legMeters(legIndex: Int, in ordered: [Waypoint]) -> Double {
        if let trip = activeTrip {
            let legs = trip.legDistancesMeters(snappedCoords: snappedRouteCoords)
            if legIndex >= 0, legIndex < legs.count, legs[legIndex] > 0 {
                return legs[legIndex]
            }
        }
        let a = ordered[legIndex].coordinate
        let b = ordered[legIndex + 1].coordinate
        return SmartInsert.haversine(a, b)
    }

    /// Other 1-based stop indices that share the selected waypoint's coord
    /// (out-and-back trips revisit the same place — Cantwell as stop 1, 9,
    /// 12). Excludes the selected waypoint itself. Same coord-key rounding
    /// (6 decimals ≈ 11 cm) as the marker-dedup in ExpeditionMapView so the
    /// callout and the marker agree on what counts as "the same place".
    private func additionalPassNumbers(for selected: Waypoint, in ordered: [Waypoint]) -> [Int] {
        let key = coordKey(selected)
        var result: [Int] = []
        for (i, wp) in ordered.enumerated() where wp.id != selected.id {
            if coordKey(wp) == key { result.append(i + 1) }
        }
        return result
    }

    private func coordKey(_ wp: Waypoint) -> String {
        String(format: "%.6f|%.6f", wp.lat, wp.lon)
    }

    private func handleSheetWaypointDeleted(_ snapshot: DeletedStopSnapshot) {
        if selectedWaypointID == snapshot.id {
            withAnimation(.smooth(duration: 0.2)) { selectedWaypointID = nil }
        }
        if recentlyAddedWaypoint?.id == snapshot.id {
            withAnimation(.smooth(duration: 0.2)) { recentlyAddedWaypoint = nil }
        }
        // rr71: dropped the "Removed from trip — Undo" toast emission.
        // The trash button is now immediate-delete with no undo overlay;
        // the user re-adds via search if it was a mistake. The dormant
        // toast view block + undoDelete + scheduleDeletedToastDismiss stay
        // in the file in case we want the undo back later — they're a
        // no-op chain since recentlyDeletedSnapshot is never populated.
        _ = snapshot
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
        return "\(DistanceFormat.string(meters: meters, useMiles: tweaksStore.distanceUnitIsMiles)) from \(wp.label ?? "the route")"
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
