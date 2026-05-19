// Trip bottom sheet (v1).
//
// State-driven detent — collapsed | overview | full — animated via simple
// height transition. Custom container (not SwiftUI's `.sheet`) so the user
// can't accidentally dismiss it; the trip is always present.
//
// Waypoint list uses `List` with `.onMove` (drag-to-reorder) and `.onDelete`
// (swipe-to-delete). Persistence directly via SwiftData @Environment.

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

struct TripBottomSheet: View {
    let trip: Trip
    @Binding var detent: TripSheetDetent
    let onTapWaypoint: (Waypoint) -> Void
    let onWaypointDeleted: (Waypoint) -> Void

    @Environment(\.modelContext) private var modelContext
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let targetHeight = detent.height(in: geo.size.height)
            // Drag offset: positive means dragged DOWN (toward collapsed).
            let effectiveHeight = max(60, targetHeight - dragOffset)

            VStack(spacing: 0) {
                grabHandle
                summary
                if detent != .collapsed {
                    Divider().opacity(0.3)
                    waypointList
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
                        if dy > 70 {        // swiped down → less expanded
                            withAnimation(.smooth(duration: 0.3)) { detent = collapseFrom(detent) }
                        } else if dy < -70 { // swiped up → more expanded
                            withAnimation(.smooth(duration: 0.3)) { detent = expandFrom(detent) }
                        }
                    }
            )
            .animation(.smooth(duration: 0.25), value: detent)
        }
    }

    // MARK: - Pieces

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
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(tripAccent)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(summaryLine)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            tripStatChip(value: stopsCount, label: "stops")
            tripStatChip(value: distanceText, label: "km")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
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

    // MARK: - Mutations

    private func reorder(from source: IndexSet, to destination: Int) {
        var current = trip.orderedWaypoints
        current.move(fromOffsets: source, toOffset: destination)
        // Renumber .order to match new sequence.
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
        // Renumber remaining waypoints.
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

    /// Naive total — straight-line distance between consecutive waypoints.
    /// Real distance comes from the routing layer's snap-to-road result.
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
