// Category shortcut rows shown in the search dropdown's EMPTY state — i.e.
// when the field is open but nothing's typed yet (AlaskaRouter-unir). Lives on
// the same .thinMaterial surface as SearchResultsView so the two read as one
// dropdown: type → suggestions; empty → these shortcuts. Tapping a row fires
// that category's group search, exactly like committing a typed search.
//
// Deliberately a SHORT, curated set — past a few, scanning is slower than just
// typing.

import SwiftUI

struct SearchShortcut: Identifiable {
    let id = UUID()
    let label: String
    let category: String        // canonical place_meta.category key
    let systemImage: String
}

struct SearchShortcutsView: View {
    let shortcuts: [SearchShortcut]
    let onTap: (SearchShortcut) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.id) { idx, s in
                Button { onTap(s) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: s.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                        Text(s.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                if idx < shortcuts.count - 1 { Divider().opacity(0.4) }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}
