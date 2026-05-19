// Trip bottom sheet (v1).
//
// State-driven detent — collapsed | overview | full — animated via simple
// height transition. Custom container (not SwiftUI's `.sheet`) so the user
// can't accidentally dismiss it; the trip is always present.
//
// Two modes:
//   - .stops  : trip header (name + tappable rename + chevron-to-switch) plus
//               the waypoint list (or empty-state hint if no stops yet).
//   - .trips  : list of all trips (tap row → switch active; trash → delete);
//               new-trip row creates an empty trip with default name.

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
    let onWaypointDeleted: (Waypoint) -> Void

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
                    Divider().opacity(0.3)
                    switch mode {
                    case .stops: stopsBody
                    case .trips: tripsBody
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: effectiveHeight, alignment: .top)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 18, y: -2)
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
            .fill(.secondary.opacity(0.45))
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.smooth(duration: 0.3)) { detent = detent.next }
            }
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(tripAccent)
                .frame(width: 12, height: 12)

            // Trip name + summary; tap → switches between modes.
            Button(action: toggleMode) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode == .stops ? trip.name : "Trips")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: mode == .stops ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(mode == .stops ? summaryLine : tripsSubtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Pencil — rename the currently-active trip.
            if mode == .stops {
                Button(action: openRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if mode == .stops {
                tripStatChip(value: stopsCount, label: "stops")
                tripStatChip(value: distanceText, label: "km")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
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
                .foregroundStyle(.secondary)
            Text("No stops yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Use the search bar above to find a place and add it.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer(minLength: 0)
        }
    }

    private var waypointList: some View {
        List {
            ForEach(trip.orderedWaypoints, id: \.id) { wp in
                waypointRow(wp)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                    .contentShape(Rectangle())
                    .onTapGesture { onTapWaypoint(wp) }
            }
            .onMove(perform: reorder)
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private func waypointRow(_ wp: Waypoint) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tripAccent.opacity(0.18))
                    .frame(width: 28, height: 28)
                Text("\(wp.order + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tripAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(wp.label ?? "Untitled stop")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(wp.category?.replacingOccurrences(of: "_", with: " ") ?? "stop")
                    Text("·")
                    Text(String(format: "%.3f, %.3f", wp.lat, wp.lon))
                }
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
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
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(isActive ? tripAccent : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(t.waypoints.count) stops")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { tripPendingDelete = t }) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(red: 0.78, green: 0.32, blue: 0.20).opacity(0.85))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var newTripRow: some View {
        Button(action: createNewTrip) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color(red: 0.78, green: 0.32, blue: 0.20))
                Text("New Trip")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
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

    // MARK: - Mutations (waypoints)

    private func reorder(from source: IndexSet, to destination: Int) {
        var current = trip.orderedWaypoints
        current.move(fromOffsets: source, toOffset: destination)
        for (i, wp) in current.enumerated() {
            wp.order = i
        }
        try? modelContext.save()
    }

    private func delete(at offsets: IndexSet) {
        let ordered = trip.orderedWaypoints
        for idx in offsets {
            guard idx < ordered.count else { continue }
            let victim = ordered[idx]
            modelContext.delete(victim)
            onWaypointDeleted(victim)
        }
        let remaining = trip.orderedWaypoints.filter { wp in
            !offsets.contains(where: { ordered[$0].id == wp.id })
        }
        for (i, wp) in remaining.enumerated() {
            wp.order = i
        }
        try? modelContext.save()
    }

    // MARK: - Computed

    private var tripAccent: Color {
        let t = trip.color.swiftUIColor
        return Color(red: t.red, green: t.green, blue: t.blue)
    }

    private var stopsCount: String { "\(trip.waypoints.count)" }

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

    private func tripStatChip(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
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
