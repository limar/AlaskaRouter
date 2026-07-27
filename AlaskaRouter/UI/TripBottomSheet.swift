// Trip bottom sheet (v1).
//
// State-driven detent — collapsed | overview | full — animated via simple
// height transition. Custom container (not SwiftUI's `.sheet`) so the user
// can't accidentally dismiss it; the trip is always present.
//
// Two modes:
//   - .stops  : trip header (eyebrow + serif name + chevron-to-switch +
//               rename pencil) plus a stat strip and the stops list inside
//               a soft white inset card. Block separators are HEADER strips
//               (square chip + serif name + "N stops" subline) — visually
//               distinct from stop rows so they're never confused for stops.
//               Stop rows are indented under their block header with a small
//               white-fill colored-stroke numbered pip.
//   - .trips  : list of all trips (tap row → switch active; trash → delete);
//               new-trip row creates an empty trip with default name.
//
// Aligned to design/mocks/sheet.jsx — see AlaskaRouter-9634. Palette + serif
// helpers live in SheetPalette.swift.

import SwiftUI
import SwiftData
import CoreLocation
import UniformTypeIdentifiers
import UIKit

enum TripSheetDetent: CaseIterable {
    case collapsed   // ~ 100 pt — trip name + summary line
    case overview    // ~ 45 % screen — waypoint list, compact
    case full        // ~ 85 % screen — waypoint list, room for edit controls

    func height(in containerHeight: CGFloat) -> CGFloat {
        switch self {
        case .collapsed: return 100
        case .overview:  return containerHeight * 0.45
        case .full:      return containerHeight * 0.85
        }
    }

    var next: TripSheetDetent {
        switch self {
        case .collapsed: return .overview
        case .overview:  return .full
        case .full:      return .collapsed
        }
    }
}

enum SheetMode { case stops, trips }

struct TripBottomSheet: View {
    let trip: Trip
    @Binding var detent: TripSheetDetent
    @Binding var mode: SheetMode
    /// Snapped road geometry for the active trip (nil when offline / not yet
    /// routed) — used to compute road-stretch lengths (AlaskaRouter-ssl1).
    var snappedRouteCoords: [CLLocationCoordinate2D]? = nil
    let onTapWaypoint: (Waypoint) -> Void
    let onWaypointDeleted: (DeletedStopSnapshot) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    // Live drag offset, accumulated during a drag gesture and reset to 0 on
    // release INSIDE the same withAnimation block that sets the new detent
    // (AlaskaRouter-p9xr). Previously this was @GestureState, which auto-
    // resets to 0 immediately on gesture end — that reset happened OUTSIDE
    // the detent's withAnimation, so the sheet visibly snapped back to its
    // pre-drag detent for one frame before animating to the new one. The
    // jump-and-rebound the user reported.
    @State private var dragOffset: CGFloat = 0

    // Rename alert
    @State private var renameAlertShown = false
    @State private var renameDraft = ""

    // Delete confirmation
    @State private var tripPendingDelete: Trip?

    // Collapsed blocks (AlaskaRouter-xq6w). Keyed by the block header's stable
    // TripListItem id ("block-0" or "sep-<uuid>"). Ephemeral per session — a
    // viewing convenience to tame long itineraries.
    @State private var collapsedBlockIDs: Set<String> = []

    // The stop currently armed for the swipe-reveal delete (AlaskaRouter-0rh9,
    // Step B of 53x1). Single value, so arming a new row automatically dismisses
    // any other. nil = no row armed.
    @State private var armedDeleteID: UUID? = nil

    // Trip file export/import (AlaskaRouter-h113).
    @State private var importerShown = false
    @State private var importError: String?

    // Export share-sheet preview (AlaskaRouter-56kj): an offline map snapshot of
    // the first waypoint, rendered async and fed to SharePreview. nil until the
    // first render lands (SharePreview falls back to the app icon meanwhile).
    @State private var tripPreviewImage: Image?

    var body: some View {
        GeometryReader { geo in
            let targetHeight = detent.height(in: geo.size.height)
            let effectiveHeight = max(60, targetHeight - dragOffset)

            VStack(spacing: 0) {
                grabHandle
                summary
                if detent != .collapsed {
                    switch mode {
                    case .stops: stopsBody
                    case .trips: tripsBody
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: effectiveHeight, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                // Warm-paper tint — pulls .thinMaterial away from "iOS grey
                // glass" toward "ranger-station atlas" (AlaskaRouter-9634).
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SheetPalette.surfaceTint)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(SheetPalette.surfaceTopHairline, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.10), radius: 18, y: -2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let dy = value.translation.height
                        let newDetent: TripSheetDetent =
                            dy >  70 ? collapseFrom(detent) :
                            dy < -70 ? expandFrom(detent)   :
                            detent
                        // Reset dragOffset and set the new detent in a single
                        // animation transaction — SwiftUI interpolates the
                        // `targetHeight - dragOffset` expression smoothly from
                        // (old detent, current offset) to (new detent, 0)
                        // without the pre-fix one-frame "snap-back" pop.
                        withAnimation(.smooth(duration: 0.3)) {
                            detent = newDetent
                            dragOffset = 0
                        }
                    }
            )
            .animation(.smooth(duration: 0.25), value: detent)
            .animation(.smooth(duration: 0.2), value: mode)
        }
        .alert("Rename trip", isPresented: $renameAlertShown) {
            TextField("Trip name", text: $renameDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                TripStore.rename(trip, to: renameDraft, in: modelContext)
            }
        }
        .alert(
            "Delete '\(tripPendingDelete?.name ?? "")'?",
            isPresented: Binding(
                get: { tripPendingDelete != nil },
                set: { if !$0 { tripPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { tripPendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let t = tripPendingDelete {
                    TripStore.delete(t, in: modelContext)
                    tripPendingDelete = nil
                }
            }
        } message: {
            Text("All stops in this trip will be removed. This cannot be undone.")
        }
        .fileImporter(
            isPresented: $importerShown,
            allowedContentTypes: [.alaskaRouterTrip, .json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        // Pre-render the export preview so it's ready when the menu opens.
        .onAppear { regenerateTripPreview() }
        .onChange(of: previewSignature) { _, _ in regenerateTripPreview() }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Header

    private var grabHandle: some View {
        Capsule()
            .fill(SheetPalette.dragHandle)
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.smooth(duration: 0.3)) { detent = detent.next }
            }
    }

    /// Header eyebrow + serif trip name + chevron-mode-toggle + rename pencil.
    /// At .collapsed the summary line also shows the stop/distance counts so
    /// the trip stat strip below (which only renders at .overview/.full) is
    /// not the only place that info appears.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: toggleMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Eyebrow — small uppercase label
                        Text(mode == .stops ? "Active Trip" : "Trips")
                            .font(.sheetSans(11, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(SheetPalette.textEyebrow)

                        // Trip name (serif) + chevron
                        HStack(spacing: 6) {
                            Text(mode == .stops ? trip.name : "All trips")
                                .font(.sheetSerif(20, weight: .semibold))
                                .foregroundStyle(SheetPalette.textStrong)
                                .lineLimit(1)
                            Image(systemName: mode == .stops ? "chevron.down" : "chevron.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SheetPalette.textMuted)
                        }

                        // Subline — at .collapsed this is the only place stats
                        // show; at .overview/.full the strip below replaces this.
                        if detent == .collapsed {
                            Text(mode == .stops ? summaryLine : tripsSubtitle)
                                .font(.sheetSans(12, weight: .regular))
                                .foregroundStyle(SheetPalette.textMuted)
                                .padding(.top, 1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if mode == .stops {
                    tripActionsMenu
                }
            }

            // Stat strip — only at .overview / .full. The .collapsed state
            // shows stats in the subline instead.
            if detent != .collapsed && mode == .stops {
                statStrip
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    /// Trip-level actions: rename, export to a `.akrtrip` file (share sheet /
    /// AirDrop / Files), and import one (AlaskaRouter-h113). The `ShareLink`
    /// builds the document lazily when the menu opens, so the segment-cache
    /// lookups in `TripDocument.export` only run on demand.
    private var tripActionsMenu: some View {
        Menu {
            Button(action: openRename) {
                Label("Rename", systemImage: "pencil")
            }
            ShareLink(
                item: ExportedTripFile(
                    document: TripDocument.export(trip, context: modelContext),
                    baseName: TripFileNaming.sanitizedBaseName(trip.name)
                ),
                preview: SharePreview(trip.name, image: tripPreviewImage ?? tripFilePreviewImage)
            ) {
                Label("Export Trip…", systemImage: "square.and.arrow.up")
            }
            Button { importerShown = true } label: {
                Label("Import Trip…", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SheetPalette.textMuted)
                .frame(width: 30, height: 30)
                .background(Color.black.opacity(0.05), in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Branded share-sheet thumbnail (AlaskaRouter-h113): the app icon, loaded
    /// from the bundled document-icon PNG, so the share preview shows our mark
    /// instead of the white schematic default. Purely cosmetic — falls back to
    /// an SF Symbol only if the bundled asset is somehow absent.
    private var tripFilePreviewImage: Image {
        if let url = Bundle.main.url(forResource: "TripDocumentIcon-320", withExtension: "png"),
           let ui = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: ui)
        }
        return Image(systemName: "map")
    }

    /// Changes whenever the preview-relevant trip state changes (first stop's
    /// identity/position, or the trip color), so we re-render the snapshot.
    private var previewSignature: String {
        let first = trip.orderedWaypoints.first
        let coord = first.map { String(format: "%.4f,%.4f", $0.lat, $0.lon) } ?? "none"
        return "\(trip.id.uuidString)|\(trip.colorRaw)|\(first?.id.uuidString ?? "empty")|\(coord)"
    }

    /// Render the offline map snapshot for the export preview. Centers on the
    /// first waypoint (with its name); an empty trip falls back to a generic
    /// Alaska center with no name pill (AlaskaRouter-56kj).
    private func regenerateTripPreview() {
        let first = trip.orderedWaypoints.first
        let center = first?.coordinate
            ?? CLLocationCoordinate2D(latitude: 63.07, longitude: -151.0)  // Denali massif
        let c = trip.color.swiftUIColor
        let markerColor = UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        TripPreviewRenderer.renderPreview(
            center: center,
            name: first?.label,
            markerColor: markerColor
        ) { image in
            if let image { tripPreviewImage = Image(uiImage: image) }
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let imported = try TripFileImport.importFile(at: url, into: modelContext)
                TripStore.setActive(imported)
                withAnimation(.smooth(duration: 0.2)) { mode = .stops }
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    /// Three-cell stat strip — Distance / Stops / Blocks. The mock has a
    /// fourth "OFFLINE Ready" cell; we drop it for v1 because the app is
    /// offline-by-design (the tile pack ships in the bundle), so a status
    /// pill that always reads "Ready" is noise. Revisit when v2 starts
    /// fetching tiles dynamically.
    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(label: "Distance", value: distanceText)
            statDivider
            statCell(label: "Stops", value: stopsCount)
            statDivider
            statCell(label: "Blocks", value: blocksCount)
        }
    }

    private func statCell(label: String, value: String, color: Color = SheetPalette.textStrong) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.sheetSans(10, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(SheetPalette.textMuted)
                .lineLimit(1)
            Text(value)
                .font(.sheetSerif(15, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(SheetPalette.statDivider)
            .frame(width: 1, height: 22)
            .padding(.horizontal, 8)
    }

    // MARK: - .stops mode

    @ViewBuilder
    private var stopsBody: some View {
        if trip.orderedWaypoints.isEmpty {
            emptyStopsHint
        } else {
            waypointList
        }
    }

    private var emptyStopsHint: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 30)
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(SheetPalette.textMuted)
            Text("No stops yet")
                .font(.sheetSerif(16, weight: .semibold))
                .foregroundStyle(SheetPalette.textStrong)
            Text("Use the search bar above to find a place and add it.")
                .font(.sheetSans(13))
                .foregroundStyle(SheetPalette.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer(minLength: 0)
        }
    }

    /// The stops list, wrapped in a soft white inset card (mock §"Stops list
    /// with embedded block dividers"). Block separators are rendered as
    /// HEADER strips, not stop-shaped rows — so they read as section titles.
    private var waypointList: some View {
        let entries = visibleEntries()
        let stopColorByID = stopColorByIDMap()
        // Computed once per render: per-leg road lengths (indexed by position
        // in orderedWaypoints) + a waypoint→position map, so the rail can label
        // each leg by POSITION rather than the `.order` field (jhw8).
        let legs = TripGeometryCache.shared.legDistances(for: trip, snappedCoords: snappedRouteCoords)
        let posByID = Dictionary(
            uniqueKeysWithValues: trip.orderedWaypoints.enumerated().map { ($1.id, $0) }
        )
        return List {
            ForEach(entries, id: \.item.id) { entry in
                row(for: entry.item, stopColorByID: stopColorByID, legs: legs, posByID: posByID)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
            }
            .onMove(perform: reorderListItems)
            .onDelete(perform: deleteListItems)

            // The bottom "Add block separator" row is gone (AlaskaRouter-ucyl).
            // Its only behaviour was to insert a separator near the END of the
            // trip and leave the user dragging it up past 40 rows — the exact
            // thing the Alaska trip complained about. Every gap now carries its
            // own split control, so there is nothing left for it to do.
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 1)
    }

    /// The rows actually shown, each paired with its index in the full
    /// `trip.listItems`. Stops of collapsed blocks are omitted; the block's
    /// header row always remains. The retained full index lets the reorder /
    /// delete handlers translate visible offsets back to model operations
    /// (AlaskaRouter-xq6w).
    private func visibleEntries() -> [(full: Int, item: TripListItem)] {
        var out: [(Int, TripListItem)] = []
        var collapsedNow = false
        for (i, item) in trip.listItems.enumerated() {
            switch item {
            case .blockHeader:
                collapsedNow = collapsedBlockIDs.contains(item.id)
                out.append((i, item))
            case .stop:
                if !collapsedNow { out.append((i, item)) }
            }
        }
        return out
    }

    /// Toggle a block's collapsed state, animating the stop rows in/out.
    private func toggleCollapse(_ headerID: String) {
        withAnimation(.snappy(duration: 0.28)) {
            if collapsedBlockIDs.contains(headerID) {
                collapsedBlockIDs.remove(headerID)
            } else {
                collapsedBlockIDs.insert(headerID)
            }
        }
    }

    /// Map each waypoint's id to the color of the block it belongs to. Used to
    /// color the small numbered badge on each stop row.
    private func stopColorByIDMap() -> [UUID: Color] {
        var map: [UUID: Color] = [:]
        for b in trip.blocks {
            let c = swiftUIColor(b.color)
            for wp in b.waypoints { map[wp.id] = c }
        }
        return map
    }

    @ViewBuilder
    private func row(for item: TripListItem, stopColorByID: [UUID: Color], legs: [Double], posByID: [UUID: Int]) -> some View {
        switch item {
        case .stop(let wp):
            waypointRow(wp, accent: stopColorByID[wp.id] ?? tripAccent, legs: legs, posByID: posByID)
        case let .blockHeader(separator, blockIndex, color, displayName):
            // Block 0's header is synthetic (separator == nil) — pin it at the
            // top of the list and hide the drag handle so users can't try to
            // reorder or delete it (pufj).
            let isSynthetic = (separator == nil)
            let headerID = item.id
            let isCollapsed = collapsedBlockIDs.contains(headerID)
            blockHeaderRow(
                blockIndex: blockIndex,
                color: swiftUIColor(color),
                displayName: displayName,
                isSynthetic: isSynthetic,
                isCollapsed: isCollapsed,
                onToggle: { toggleCollapse(headerID) }
            )
            // Separator headers are draggable again (AlaskaRouter-exf0). Moving
            // a header slides the SEPARATOR — the boundary between two blocks
            // — to anchor at a different waypoint; it doesn't reorder road
            // stretches. Synthetic block 0 has no separator; collapsed headers
            // are locked (their dot column is hidden anyway).
            .moveDisabled(isSynthetic || isCollapsed)
            .deleteDisabled(isSynthetic)
        }
    }

    /// Block HEADER strip — square color chip with white number + serif name
    /// + "N stops" subline. Distinctly NOT shaped like a stop row, so users
    /// don't confuse a block separator for a waypoint. (Was previously a
    /// rounded pill, which the mock-alignment work in AlaskaRouter-9634
    /// flagged as the root cause of "separators visibly resemble waystops.")
    private func blockHeaderRow(blockIndex: Int, color: Color, displayName: String, isSynthetic: Bool = false, isCollapsed: Bool = false, onToggle: @escaping () -> Void = {}) -> some View {
        let dragColWidth: CGFloat = 12
        // Wrapping the header in a Button (vs the previous .onTapGesture) lets
        // SwiftUI's gesture system route tap-vs-swipe correctly — .onTapGesture
        // was swallowing List's horizontal swipe, so the separator's
        // swipe-to-delete affordance went missing (AlaskaRouter-00iw).
        return
            HStack(spacing: 10) {
                // Leading drag column — 6-dot grip when the separator is
                // movable, invisible spacer otherwise (synthetic block 0 or
                // collapsed). Reserving the column even when empty keeps the
                // leading edge aligned with stop rows so the column reads as
                // one grip rail down the list (AlaskaRouter-exf0).
                Group {
                    if isSynthetic || isCollapsed {
                        Color.clear
                    } else {
                        HStack(spacing: 2) {
                            ForEach(0 ..< 2, id: \.self) { _ in
                                VStack(spacing: 2) {
                                    ForEach(0 ..< 3, id: \.self) { _ in
                                        Circle()
                                            .fill(SheetPalette.textStrong.opacity(0.45))
                                            .frame(width: 2, height: 2)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: dragColWidth)

                // Square chip with number — clearly different from the round
                // pip on a stop row.
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color)
                        .frame(width: 22, height: 22)
                    Text("\(blockIndex + 1)")
                        .font(.sheetSans(11, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    // Italic + muted — quieter "section label" voice, distinct
                    // from waypoint names (solid serif semibold). Matches the
                    // mock's auto-name treatment for block headers.
                    Text(displayName)
                        .font(.sheetSerif(14, weight: .semibold))
                        .italic()
                        .foregroundStyle(SheetPalette.textMuted)
                        .lineLimit(1)
                    Text(blockSubline(blockIndex: blockIndex))
                        .font(.sheetSans(10.5))
                        .tracking(0.4)
                        .foregroundStyle(SheetPalette.textMuted)
                }

                Spacer(minLength: 0)

                // Trailing-edge disclosure chevron — always visible so the
                // tap-to-collapse affordance is discoverable (AlaskaRouter-tsvw,
                // refined after the first try lost the affordance). Block
                // reordering is intentionally dropped — moving whole road
                // stretches around isn't a real use case; stop rows remain
                // draggable.
                Button(action: onToggle) {
                    Image(
                        systemName: isCollapsed
                            ? "chevron.right" : "chevron.down"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SheetPalette.textMuted.opacity(0.7))
                }.buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(SheetPalette.blockHeaderBg)
            .overlay(
                // Top hairline divides this block from the previous block.
                // Suppressed via opacity on the very first row (which sits at
                // the top of the card).
                VStack {
                    Rectangle()
                        .fill(SheetPalette.cardBorder)
                        .frame(height: 0.5)
                    Spacer()
                }
                .opacity(blockIndex == 0 ? 0 : 1)
            )
            .contentShape(Rectangle())
        }

    /// Stop row — small white-fill numbered pip with colored stroke, serif
    /// name, sans kind hint. Always indented under its block header — every
    /// block (including block 0) has a header per pufj, so all stops sit
    /// uniformly indented relative to the header above them
    /// (AlaskaRouter-4rly fixed the conditional-indent bug here).
    private func waypointRow(_ wp: Waypoint, accent: Color, legs: [Double], posByID: [UUID: Int]) -> some View {
        let railWidth: CGFloat = 24
        // 6-dot drag handle column on the leading edge (AlaskaRouter-zvhr,
        // mock-aligned). Same reserved column on the leg band above so the
        // rail's x-position stays continuous.
        let dragColWidth: CGFloat = 12
        // Extra leading indent for stops only — placed between the drag
        // column and the rail so the pip sits past the block-header chip
        // (AlaskaRouter-exf0). Currently 0; the HStack's natural 10pt
        // spacing on each side of the placeholder still contributes the gap
        // that lands the rail center on the chip right edge. Mirrored on the
        // leg band so the rail stays aligned.
        let stopIndentExtra: CGFloat = 0
        let railColor = accent.opacity(0.45)
        // Index by POSITION in orderedWaypoints (not the `.order` field, which
        // isn't guaranteed 0-based), so the first stop never gets an incoming
        // leg and each label is the stretch arriving at this stop (jhw8).
        let pos = posByID[wp.id] ?? 0
        let hasIncoming = pos >= 1
        let isLast = pos >= legs.count          // legs.count == stops − 1
        let legText: String? = {
            guard pos >= 1, pos - 1 < legs.count, legs[pos - 1] > 0 else { return nil }
            return DistanceFormat.string(meters: legs[pos - 1], useMiles: useMiles)
        }()

        return VStack(spacing: 0) {
            // Incoming-leg band — the leg distance sits ON the connector,
            // between the previous pip and this one. Skipped for the first stop.
            // The connector band carries the leg distance AND the "split here"
            // control. It renders for every incoming leg now, not only ones
            // with a known distance — an unrouted leg is still a gap you can
            // break the day at (AlaskaRouter-ucyl).
            if hasIncoming {
                HStack(spacing: 10) {
                    Color.clear.frame(width: dragColWidth)        // mirror dot column
                    Color.clear.frame(width: stopIndentExtra)     // mirror stop indent
                    ZStack {
                        Rectangle()
                            .fill(railColor)
                            .frame(width: 1.5)
                        if let legText {
                            Text(legText)
                                .font(.sheetSans(10, weight: .bold))
                                .tracking(0.2)
                                .foregroundStyle(accent)
                                .fixedSize()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Capsule()
                                    .fill(Color.white)
                                    .strokeBorder(accent, lineWidth: 0.8))
                        }
                    }
                    .frame(width: railWidth)
                    // Split control sits in the gap BETWEEN two stops, because
                    // that is literally what a separator is — and it means the
                    // day breaks exactly where the user tapped, instead of
                    // appearing near the end of the trip to be dragged up.
                    // Hidden where a separator already occupies this gap.
                    if !hasSeparatorBefore(wp) {
                        Button(action: { splitBlock(before: wp) }) {
                            Image(systemName: "scissors")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(SheetPalette.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().stroke(SheetPalette.cardBorder,
                                                             style: StrokeStyle(lineWidth: 0.5, dash: [2.5, 2.5])))
                                // The glyph is deliberately small so the
                                // resting list stays quiet, but the tappable
                                // area must not be: pad the hit shape out to a
                                // comfortable target without drawing anything.
                                .frame(width: 60, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Start a new block at \(wp.label ?? "this stop")")
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 17)
            }

            // Step B of 53x1 (AlaskaRouter-0rh9) — swipe-reveal: tap minus
            // arms the row, content slides left, red Delete reveals trailing.
            let isArmed = (armedDeleteID == wp.id)
            ZStack(alignment: .trailing) {
                // Trailing-layer red Delete — sits behind the row content,
                // revealed when content slides left.
                Button(action: {
                    deleteWaypoint(wp)
                    armedDeleteID = nil
                }) {
                    // Approximation of iOS's swipe-to-delete pill: system red
                    // (dark-mode-aware via UIColor.systemRed), rounded corners,
                    // SF Symbol trash icon + "Delete" label stacked. The pill
                    // is inset a few points so it reads as a pill rather than
                    // filling the row edge-to-edge. Corner radius / inset are
                    // educated guesses since Apple doesn't expose the exact
                    // values — colour and glyph are the stable contracts.
                    // .fixedSize() on the content prevents the wrap-into-many
                    // -lines bug at width 0; .clipped() hides overflow.
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .systemRed))
                            .padding(.vertical, 4)
                            .padding(.trailing, 4)
                        VStack(spacing: 2) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Delete")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .fixedSize()
                    }
                    .frame(width: isArmed ? 84 : 0)
                    .frame(maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(isArmed)

                HStack(spacing: 10) {
                    // 6-dot drag handle on the leading edge (AlaskaRouter-zvhr,
                    // mock-aligned). Two columns × three rows of small filled
                    // circles, ~32% alpha. Lighter weight than line.3.horizontal
                    // and indents the stop visibly beneath its block header.
                    // Mock-faithful tight grid: 2pt circles, 2pt gaps
                    // (4pt center-to-center) so the cluster reads as one compact
                    // glyph rather than a sparse halftone pattern.
                    HStack(spacing: 2) {
                        ForEach(0 ..< 2, id: \.self) { _ in
                            VStack(spacing: 2) {
                                ForEach(0 ..< 3, id: \.self) { _ in
                                    Circle()
                                        // 45% textStrong (darker base than the
                                        // mock's 32% textMuted) — compensates for
                                        // the translucent-sheet contrast issue
                                        // tracked in AlaskaRouter-1ag5. Diameter
                                        // pulled back to 2pt now that the pip
                                        // shrank (3lr9) so dots/pip stay
                                        // proportional.
                                        .fill(SheetPalette.textStrong.opacity(0.45))
                                        .frame(width: 2, height: 2)
                                }
                            }
                        }
                    }
                    .frame(width: dragColWidth)

                    // Extra indent: pushes pip past the block-header chip x.
                    Color.clear.frame(width: stopIndentExtra)

                    // Timeline rail: top + bottom half-segments (block-colored)
                    // with the numbered pip riding on it. Top hidden for the first
                    // stop, bottom hidden for the last (AlaskaRouter-jhw8, mock).
                    ZStack {
                        VStack(spacing: 0) {
                            Rectangle().fill(hasIncoming ? railColor : Color.clear)
                            Rectangle().fill(isLast ? Color.clear : railColor)
                        }
                        .frame(width: 1.5)

                        // Numbered pip — smaller (AlaskaRouter-3lr9, mock-aligned):
                        // 22pt → 17pt diameter, stroke 1.6 → 1.4, outer ring
                        // scaled proportionally, digit 10 → 9pt. Lighter weight,
                        // gives the rail more presence as the block-identity carrier.
                        ZStack {
                            Circle().fill(Color.white).frame(width: 17, height: 17)
                            Circle().stroke(accent, lineWidth: 1.4).frame(width: 17, height: 17)
                            Circle().stroke(SheetPalette.pipOuterRing, lineWidth: 0.6).frame(width: 18.8, height: 18.8)
                            Text("\(wp.order + 1)")
                                .font(.sheetSans(9, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(accent)
                        }
                    }
                    .frame(width: railWidth)

                    Button(action: {
                        // While armed, tapping the row body cancels (instead of
                        // selecting the waypoint) — the rule-of-thumb "tap
                        // anywhere off the red Delete dismisses." (0rh9)
                        if isArmed {
                            armedDeleteID = nil
                        } else {
                            onTapWaypoint(wp)
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wp.label ?? "Untitled stop")
                                .font(.sheetSerif(15, weight: .semibold))
                                .foregroundStyle(SheetPalette.textStrong)
                                .lineLimit(1)
                            Text(kindHint(for: wp))
                                .font(.sheetSans(11.5))
                                .foregroundStyle(SheetPalette.textMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Minus button — tap arms the row for confirmation
                    // (Step B of AlaskaRouter-53x1, 0rh9). Tapping again
                    // while armed dismisses. Apple's native swipe-to-delete
                    // remains an alternative path via List's .onDelete.
                    Button(action: {
                        armedDeleteID = isArmed ? nil : wp.id
                    }) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(SheetPalette.textMuted)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                .offset(x: isArmed ? -84 : 0)
            }
            .animation(.snappy(duration: 0.25), value: armedDeleteID)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
    }


    /// Distances in miles (vs km) per the user's tweak setting. Read here so
    /// SwiftUI tracks the dependency and displays update when it toggles.
    private var useMiles: Bool { TweaksStore.shared.distanceUnitIsMiles }

    private func kindHint(for wp: Waypoint) -> String {
        // Friendly category label only. The leg distance moved onto the
        // timeline rail (jhw8) so it reads as the stretch between two stops.
        CategoryLabel.display(wp.category)
    }

    /// Block header subline: "N stops" plus the block's road length.
    private func blockSubline(blockIndex: Int) -> String {
        let count = stopCountInBlock(blockIndex: blockIndex)
        let stopsText = count == 1 ? "1 stop" : "\(count) stops"
        let blocks = trip.blocks
        guard blockIndex >= 0, blockIndex < blocks.count else { return stopsText }
        let m = TripGeometryCache.shared.blockDistance(blocks[blockIndex], for: trip, snappedCoords: snappedRouteCoords)
        guard m > 0 else { return stopsText }
        return "\(stopsText) · \(DistanceFormat.string(meters: m, useMiles: useMiles))"
    }

    private func stopCountInBlock(blockIndex: Int) -> Int {
        let blocks = trip.blocks
        guard blockIndex >= 0, blockIndex < blocks.count else { return 0 }
        return blocks[blockIndex].waypoints.count
    }

    // MARK: - .trips mode

    private var tripsBody: some View {
        List {
            ForEach(allTrips, id: \.id) { t in
                tripRow(t)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
            }
            newTripRow
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 14))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private func tripRow(_ t: Trip) -> some View {
        let isActive = (t.id == trip.id)
        return HStack(spacing: 12) {
            Button(action: { switchTo(t) }) {
                HStack(spacing: 12) {
                    // Active trip: palette-rendered checkmark — explicit
                    // WHITE inner + accent outer so the ✓ is visible in
                    // dark mode (where a cutout would just show the sheet).
                    // Inactive trip: thin outline circle in muted text.
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .regular))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, tripAccent)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(SheetPalette.textMuted)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name)
                            .font(.sheetSerif(15, weight: .semibold))
                            .foregroundStyle(SheetPalette.textStrong)
                            .lineLimit(1)
                        Text("\(t.waypoints.count) stops")
                            .font(.sheetSans(11.5))
                            .foregroundStyle(SheetPalette.textMuted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { tripPendingDelete = t }) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(SheetPalette.destructive, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var newTripRow: some View {
        Button(action: createNewTrip) {
            HStack(spacing: 12) {
                // Additive action — warm-brand accent (NOT destructive red).
                // Same colored-disc-white-inner-glyph treatment as the
                // search "+" so all additive affordances share one color.
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, SheetPalette.accentWarm)
                Text("New Trip")
                    .font(.sheetSerif(15, weight: .semibold))
                    .foregroundStyle(SheetPalette.textStrong)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func toggleMode() {
        withAnimation(.smooth(duration: 0.2)) {
            mode = (mode == .stops) ? .trips : .stops
        }
        if detent == .collapsed {
            withAnimation(.smooth(duration: 0.3)) { detent = .overview }
        }
    }

    private func openRename() {
        renameDraft = trip.name
        renameAlertShown = true
    }

    private func switchTo(_ t: Trip) {
        TripStore.setActive(t)
        withAnimation(.smooth(duration: 0.2)) { mode = .stops }
    }

    private func createNewTrip() {
        _ = TripStore.createEmpty(in: modelContext)
        withAnimation(.smooth(duration: 0.2)) { mode = .stops }
    }

    // MARK: - Mutations (waypoints + separators)

    /// True when a block separator already sits in the gap immediately before
    /// `wp` — i.e. this gap is already a block boundary, so offering to split
    /// it again would be a dead control.
    private func hasSeparatorBefore(_ wp: Waypoint) -> Bool {
        let stops = trip.orderedWaypoints
        guard let idx = stops.firstIndex(where: { $0.id == wp.id }), idx >= 1 else { return false }
        let anchorID = stops[idx - 1].id
        return trip.separators.contains { $0.afterWaypointID == anchorID }
    }

    /// Start a new block AT `wp` — i.e. place the separator immediately before
    /// it (AlaskaRouter-ucyl). This is the whole point of the change: the user
    /// says where the day breaks, instead of the separator appearing near the
    /// end of the trip and being dragged into place.
    private func splitBlock(before wp: Waypoint) {
        let stops = trip.orderedWaypoints
        guard let idx = stops.firstIndex(where: { $0.id == wp.id }), idx >= 1 else { return }
        let anchor = stops[idx - 1]                     // separator sits AFTER this stop
        // Don't stack two separators in the same gap.
        if trip.separators.contains(where: { $0.afterWaypointID == anchor.id }) { return }
        let sep = BlockSeparator(afterWaypointID: anchor.id)
        sep.trip = trip
        modelContext.insert(sep)
        try? modelContext.save()
    }


    /// Reorder a unified list of TripListItems. Walks the resulting sequence
    /// and:
    ///   - re-assigns waypoint.order to match the new stop sequence
    ///   - sets each separator's afterWaypointID to the id of the waypoint
    ///     immediately preceding it (or deletes the separator if no waypoint
    ///     precedes it, which makes the separator degenerate)
    private func reorderListItems(from source: IndexSet, to destination: Int) {
        // `.onMove` hands back offsets into the VISIBLE (collapse-filtered)
        // list. Translate them to offsets in the full `trip.listItems` before
        // mutating, so collapsed blocks' hidden stops travel correctly and the
        // dragged row lands before/after a collapsed block (which stays
        // collapsed) — AlaskaRouter-xq6w.
        let entries = visibleEntries()
        let full = trip.listItems
        guard let srcVisible = source.first, srcVisible < entries.count else { return }
        let srcFull = entries[srcVisible].full
        let destFull = (destination < entries.count) ? entries[destination].full : full.count
        var items = full
        items.move(fromOffsets: IndexSet(integer: srcFull), toOffset: destFull)

        var stopIndex = 0
        var lastWaypointID: UUID? = nil
        // Whether a separator already anchors to `lastWaypointID`. Two block
        // headers landing adjacent (no stop between them) would otherwise both
        // anchor to the same stop — an empty block, and a duplicate boundary
        // that crashes `Trip.blocks`. Keep the first, delete the rest.
        var anchoredCurrentStop = false
        for item in items {
            switch item {
            case .stop(let wp):
                wp.order = stopIndex
                stopIndex += 1
                lastWaypointID = wp.id
                anchoredCurrentStop = false
            case .blockHeader(let separator, _, _, _):
                // Block 0's synthetic header (separator == nil) is fixed
                // and shouldn't appear in the reorder set (`moveDisabled`
                // suppresses it); skip defensively.
                guard let sep = separator else { continue }
                if let prev = lastWaypointID, !anchoredCurrentStop {
                    sep.afterWaypointID = prev
                    anchoredCurrentStop = true
                } else {
                    // No preceding stop (top), or a separator already anchors
                    // this stop (two adjacent headers) → redundant, delete.
                    modelContext.delete(sep)
                }
            }
        }
        pruneDegenerateSeparators()
        try? modelContext.save()
    }

    private func deleteListItems(at offsets: IndexSet) {
        // Offsets index the VISIBLE (collapse-filtered) list (xq6w).
        let entries = visibleEntries()
        var deletedWaypointIDs = Set<UUID>()
        for idx in offsets {
            guard idx < entries.count else { continue }
            switch entries[idx].item {
            case .stop(let wp):
                deletedWaypointIDs.insert(wp.id)
                deleteWaypoint(wp, renumberAfter: false)
            case .blockHeader(let separator, _, _, _):
                // `deleteDisabled` on the synthetic block-0 header means
                // we should only ever see real separators here; nil = no-op.
                guard let sep = separator else { continue }
                modelContext.delete(sep)
            }
        }
        // Renumber remaining stops; prune separators whose anchor vanished.
        // lqfq: exclude the just-deleted waypoints — SwiftData still surfaces
        // them in `orderedWaypoints` until save, and renumbering THEM consumes
        // the slots the survivors should be claiming.
        trip.renumberWaypoints(excluding: deletedWaypointIDs)
        pruneDegenerateSeparators()
        try? modelContext.save()
    }

    /// Single chokepoint for waypoint deletion — captures a snapshot first so
    /// the parent can offer Undo, then removes the waypoint and (optionally)
    /// renumbers the rest. The swipe-delete path opts out of inline renumber
    /// since it does its own pass over all offsets at the end.
    private func deleteWaypoint(_ wp: Waypoint, renumberAfter: Bool = true) {
        let snapshot = DeletedStopSnapshot(
            id: wp.id,
            order: wp.order,
            coordinate: wp.coordinate,
            label: wp.label,
            category: wp.category
        )
        modelContext.delete(wp)
        onWaypointDeleted(snapshot)
        if renumberAfter {
            // lqfq: exclude the just-deleted waypoint from the renumber pass.
            trip.renumberWaypoints(excluding: wp.id)
            pruneDegenerateSeparators()
            try? modelContext.save()
        }
    }

    /// Removes separators that are degenerate (no anchor, anchor deleted, or
    /// anchor is the last waypoint → no following stops) and collapses
    /// duplicate-anchor separators down to one per stop (two separators on the
    /// same stop describe one boundary and crash `Trip.blocks`). Iterates a
    /// snapshot because `modelContext.delete` mutates `trip.separators`. This
    /// also heals a trip whose separator set was corrupted by an earlier edit.
    private func pruneDegenerateSeparators() {
        let stops = trip.orderedWaypoints
        let stopIDs = Set(stops.map(\.id))
        let lastID = stops.last?.id
        var anchorsKept = Set<UUID>()
        for sep in Array(trip.separators) {
            guard let anchor = sep.afterWaypointID,
                  stopIDs.contains(anchor),
                  anchor != lastID,
                  anchorsKept.insert(anchor).inserted
            else {
                modelContext.delete(sep)
                continue
            }
        }
    }

    private func swiftUIColor(_ c: TripColor) -> Color {
        let t = c.swiftUIColor
        return Color(red: t.red, green: t.green, blue: t.blue)
    }

    // MARK: - Computed

    private var tripAccent: Color {
        let t = trip.color.swiftUIColor
        return Color(red: t.red, green: t.green, blue: t.blue)
    }

    private var stopsCount: String { "\(trip.waypoints.count)" }

    private var blocksCount: String {
        // Number of blocks = separators + 1 (block 0 has no separator above
        // it; every separator after it starts a new block).
        return "\(trip.separators.count + 1)"
    }

    /// Total trip length — road distance (snapped) when available, else
    /// straight-line — formatted in the chosen unit (AlaskaRouter-ssl1).
    private var distanceText: String {
        DistanceFormat.string(
            meters: TripGeometryCache.shared.totalDistance(for: trip, snappedCoords: snappedRouteCoords),
            useMiles: useMiles
        )
    }

    private var summaryLine: String {
        "\(stopsCount) stops · \(distanceText)"
    }

    private var tripsSubtitle: String {
        let n = allTrips.count
        return n == 1 ? "1 trip" : "\(n) trips"
    }

    private func collapseFrom(_ d: TripSheetDetent) -> TripSheetDetent {
        switch d {
        case .full: return .overview
        case .overview: return .collapsed
        case .collapsed: return .collapsed
        }
    }

    private func expandFrom(_ d: TripSheetDetent) -> TripSheetDetent {
        switch d {
        case .collapsed: return .overview
        case .overview: return .full
        case .full: return .full
        }
    }
}
