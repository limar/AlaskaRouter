// Brief, auto-dismissing toast shown after a search result is added to the
// trip. Floats above the bottom sheet, contains an Undo button for ~4 sec.

import SwiftUI

struct AddedToTripToast: View {
    let waypointLabel: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Added to trip")
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
