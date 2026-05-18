// Floating search bar — pill collapse aesthetic (locked v1, 2026-05-18).
//
// Two states:
//   - .expanded: full-width Safari-style pill with search field, mic, profile chip
//   - .collapsed: thin oval pill below the Dynamic Island, showing the active
//     trip name + chevron — same pattern Safari uses for its address bar.
//
// Top placement relies on the parent NOT calling `.ignoresSafeArea()` so the
// inset accounts for status bar + Dynamic Island. The map underneath calls
// `.ignoresSafeArea()` on itself so it still fills the screen.

import SwiftUI

struct FloatingSearchBar: View {
    @Binding var state: FloatingSearchBarState
    @Binding var query: String
    let activeTripName: String

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .expanded:  expandedPill
            case .collapsed: collapsedPill
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.horizontal, 14)
    }

    private var expandedPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search places, peaks, fuel…", text: $query)
                .font(.system(size: 16, weight: .regular))
                .textFieldStyle(.plain)
                .submitLabel(.search)
            Spacer(minLength: 0)
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Circle()
                .fill(Color.orange.opacity(0.85))
                .frame(width: 24, height: 24)
                .overlay(Text("AK").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private var collapsedPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(activeTripName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .frame(maxWidth: 240)
        .frame(maxWidth: .infinity, alignment: .center)
        .onTapGesture { withAnimation(.smooth(duration: 0.25)) { state = .expanded } }
    }
}
