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
    let onTapWaypoint: (Waypoint) -> Void
    let onWaypointDeleted: (DeletedStopSnapshot) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @GestureState private var dragOffset: CGFloat = 0

    // Rename alert
    @State private var renameAlertShown = false
    @State private var renameDraft = ""

    // Delete confirmation
    @State private var tripPendingDelete: Trip?

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
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let dy = value.translation.height
                        if dy > 70 {
                            withAnimation(.smooth(duration: 0.3)) { detent = collapseFrom(detent) }
                        } else if dy < -70 {
                            withAnimation(.smooth(duration: 0.3)) { detent = expandFrom(detent) }
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
                    Button(action: openRename) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SheetPalette.textMuted)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
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

    /// Three-cell stat strip — Distance / Stops / Blocks. The mock has a
    /// fourth "OFFLINE Ready" cell; we drop it for v1 because the app is
    /// offline-by-design (the tile pack ships in the bundle), so a status
    /// pill that always reads "Ready" is noise. Revisit when v2 starts
    /// fetching tiles dynamically.
    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(label: "Distance", value: "\(distanceText) km")
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
        let items = trip.listItems
        let stopColorByID = stopColorByIDMap()
        return List {
            ForEach(items) { item in
                row(for: item, stopColorByID: stopColorByID)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
            }
            .onMove(perform: reorderListItems)
            .onDelete(perform: deleteListItems)

            if trip.waypoints.count >= 2 {
                addBlockRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 14, trailing: 14))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 1)
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
    private func row(for item: TripListItem, stopColorByID: [UUID: Color]) -> some View {
        switch item {
        case .stop(let wp):
            waypointRow(wp, accent: stopColorByID[wp.id] ?? tripAccent)
        case let .blockHeader(separator, blockIndex, color, displayName):
            // Block 0's header is synthetic (separator == nil) — pin it at the
            // top of the list and hide the drag handle so users can't try to
            // reorder or delete it (pufj).
            let isSynthetic = (separator == nil)
            blockHeaderRow(
                blockIndex: blockIndex,
                color: swiftUIColor(color),
                displayName: displayName,
                isSynthetic: isSynthetic
            )
            .moveDisabled(isSynthetic)
            .deleteDisabled(isSynthetic)
        }
    }

    /// Block HEADER strip — square color chip with white number + serif name
    /// + "N stops" subline. Distinctly NOT shaped like a stop row, so users
    /// don't confuse a block separator for a waypoint. (Was previously a
    /// rounded pill, which the mock-alignment work in AlaskaRouter-9634
    /// flagged as the root cause of "separators visibly resemble waystops.")
    private func blockHeaderRow(blockIndex: Int, color: Color, displayName: String, isSynthetic: Bool = false) -> some View {
        let count = stopCountInBlock(blockIndex: blockIndex)
        return HStack(spacing: 10) {
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
                Text(displayName)
                    .font(.sheetSerif(14, weight: .semibold))
                    .foregroundStyle(SheetPalette.textStrong)
                    .lineLimit(1)
                Text(count == 1 ? "1 stop" : "\(count) stops")
                    .font(.sheetSans(10.5))
                    .tracking(0.4)
                    .foregroundStyle(SheetPalette.textMuted)
            }

            Spacer(minLength: 0)

            // Drag handle — block headers participate in reorder like any
            // other list row (.onMove). Block 0's synthetic header is fixed
            // (no underlying separator to reorder), so the drag handle is
            // suppressed for it.
            if !isSynthetic {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SheetPalette.textMuted.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
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
    }

    /// Stop row — small white-fill numbered pip with colored stroke, serif
    /// name, sans kind hint. Indented if the trip has any block separators.
    private func waypointRow(_ wp: Waypoint, accent: Color) -> some View {
        let isIndented = !trip.separators.isEmpty
        return HStack(spacing: 10) {
            // Numbered pip — white fill, 1.6pt colored stroke, tabular digit.
            // Dark mode adds a thin cream ring just outside the colored stroke
            // (AlaskaRouter-yxve) so the block-color identity lifts off the
            // warm-sepia sheet background; in light mode pipOuterRing is
            // .clear so the extra Circle is a no-op.
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(accent, lineWidth: 1.6)
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(SheetPalette.pipOuterRing, lineWidth: 0.8)
                    .frame(width: 24.4, height: 24.4)
                Text("\(wp.order + 1)")
                    .font(.sheetSans(10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }

            Button(action: { onTapWaypoint(wp) }) {
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

            // Trash — instant delete; the Undo toast (AlaskaRouter-j5w1) is
            // the safety net so no confirmation alert here.
            //
            // Visual: filled destructive circle + WHITE trash on top (matches
            // the "+" and "✓" pattern from yxve so all action affordances
            // share one "colored disc, white inner symbol" language).
            Button(action: { deleteWaypoint(wp) }) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(SheetPalette.destructive, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Drag handle — the iOS-native .onMove integration uses this.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SheetPalette.textMuted.opacity(0.7))
        }
        .padding(.leading, isIndented ? 22 : 4)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
    }

    private var addBlockRow: some View {
        Button(action: addBlockSeparator) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(SheetPalette.textMuted)
                Text("Add block separator")
                    .font(.sheetSans(12, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(SheetPalette.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SheetPalette.cardBorder, style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func kindHint(for wp: Waypoint) -> String {
        let cat = wp.category?.replacingOccurrences(of: "_", with: " ") ?? "stop"
        return "\(cat) · \(String(format: "%.3f, %.3f", wp.lat, wp.lon))"
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

    private func addBlockSeparator() {
        // Place the new separator AFTER the second-to-last stop so block 2
        // visibly contains the last stop. Avoids the degenerate "separator
        // after the last waypoint" position.
        let stops = trip.orderedWaypoints
        guard stops.count >= 2 else { return }
        let anchor = stops[stops.count - 2]
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
        var items = trip.listItems
        items.move(fromOffsets: source, toOffset: destination)

        var stopIndex = 0
        var lastWaypointID: UUID? = nil
        for item in items {
            switch item {
            case .stop(let wp):
                wp.order = stopIndex
                stopIndex += 1
                lastWaypointID = wp.id
            case .blockHeader(let separator, _, _, _):
                // Block 0's synthetic header (separator == nil) is fixed
                // and shouldn't appear in the reorder set (`moveDisabled`
                // suppresses it); skip defensively.
                guard let sep = separator else { continue }
                if let prev = lastWaypointID {
                    sep.afterWaypointID = prev
                } else {
                    // Separator at the very top (no preceding stop) → delete.
                    modelContext.delete(sep)
                }
            }
        }
        pruneDegenerateSeparators()
        try? modelContext.save()
    }

    private func deleteListItems(at offsets: IndexSet) {
        let items = trip.listItems
        for idx in offsets {
            guard idx < items.count else { continue }
            switch items[idx] {
            case .stop(let wp):
                deleteWaypoint(wp, renumberAfter: false)
            case .blockHeader(let separator, _, _, _):
                // `deleteDisabled` on the synthetic block-0 header means
                // we should only ever see real separators here; nil = no-op.
                guard let sep = separator else { continue }
                modelContext.delete(sep)
            }
        }
        // Renumber remaining stops; prune separators whose anchor vanished.
        let remainingStops = trip.orderedWaypoints
        for (i, wp) in remainingStops.enumerated() { wp.order = i }
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
            let remaining = trip.orderedWaypoints
            for (i, w) in remaining.enumerated() { w.order = i }
            pruneDegenerateSeparators()
            try? modelContext.save()
        }
    }

    /// Removes separators that have no anchor or whose anchor is the very
    /// last waypoint (no following stops → degenerate block).
    private func pruneDegenerateSeparators() {
        let stops = trip.orderedWaypoints
        let stopIDs = Set(stops.map(\.id))
        let lastID = stops.last?.id
        for sep in trip.separators {
            guard let anchor = sep.afterWaypointID else {
                modelContext.delete(sep)
                continue
            }
            if !stopIDs.contains(anchor) || anchor == lastID {
                modelContext.delete(sep)
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

    private var distanceText: String {
        let coords = trip.orderedWaypoints.map(\.coordinate)
        guard coords.count >= 2 else { return "0" }
        var meters: Double = 0
        for i in 1..<coords.count {
            let a = CLLocation(latitude: coords[i - 1].latitude, longitude: coords[i - 1].longitude)
            let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            meters += a.distance(from: b)
        }
        return String(format: "%.0f", meters / 1000)
    }

    private var summaryLine: String {
        "\(stopsCount) stops · \(distanceText) km"
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
