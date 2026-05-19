// Brief, auto-dismissing toast shown after a trip mutation (add / remove).
// Floats above the bottom sheet, contains an Undo button for ~4 sec.

import SwiftUI

enum TripToastKind {
    case added, removed

    var iconName: String {
        switch self {
        case .added:   return "mappin.circle.fill"
        case .removed: return "trash.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .added:   return .green
        case .removed: return Color(red: 0.78, green: 0.32, blue: 0.20)
        }
    }

    var titleText: String {
        switch self {
        case .added:   return "Added to trip"
        case .removed: return "Removed from trip"
        }
    }
}

struct TripEditToast: View {
    let kind: TripToastKind
    let waypointLabel: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(kind.iconColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.titleText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(waypointLabel)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Back-compat shim — existing call sites stay working.
struct AddedToTripToast: View {
    let waypointLabel: String
    let onUndo: () -> Void
    var body: some View {
        TripEditToast(kind: .added, waypointLabel: waypointLabel, onUndo: onUndo)
    }
}
