// Floating search bar — pill collapse aesthetic (locked v1, 2026-05-18).
//
// Two states:
//   - .expanded:  full Safari-style pill with search field, mic, profile chip.
//                  When the field is focused, a "Cancel" button replaces the
//                  profile chip — tap it to blur the field and collapse the
//                  bar back to pill form.
//   - .collapsed: thin oval pill below the Dynamic Island, showing the active
//                  trip name + chevron. Tap to re-expand.
//
// Layout: the parent in RootView is a top-anchored VStack with standard
// keyboard avoidance — the VStack's bottom shrinks when the keyboard
// appears but its top stays put, so the bar at the top of the stack is
// unaffected. No need for this view to opt out of keyboard avoidance
// itself.

import SwiftUI

struct FloatingSearchBar: View {
    @Binding var state: FloatingSearchBarState
    @Binding var query: String
    @Binding var isFieldFocused: Bool   // mirrors @FocusState outward for RootView
    let activeTripName: String

    @FocusState private var fieldFocused: Bool

    var body: some View {
        // The bar takes only its intrinsic (pill) height — no internal Spacer.
        // The parent layout is responsible for vertical positioning; a Spacer
        // here would expand this view to fill its container and push siblings
        // (like the search-results dropdown) to the bottom of the screen.
        Group {
            switch state {
            case .expanded:  expandedPill
            case .collapsed: collapsedPill
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 14)
        .onChange(of: fieldFocused) { _, new in isFieldFocused = new }
        .onChange(of: isFieldFocused) { _, new in
            // Allow the parent to forcibly dismiss the keyboard.
            if !new && fieldFocused { fieldFocused = false }
        }
    }

    private var expandedPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search places, peaks, fuel…", text: $query)
                .font(.system(size: 16, weight: .regular))
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .submitLabel(.search)
                // Place names (Native, Russian, Athabaskan transliterations
                // like "Kotsina") aren't English words; autocorrect mangles
                // them mid-type. Disable correction + capitalization + spell.
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .keyboardType(.default)
            Spacer(minLength: 0)
            // Mic + AK chip stay visible at all times. The user dismisses by
            // tapping outside the bar (RootView's dim layer → dismissSearch).
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
        .contentShape(Capsule())
        .onTapGesture { fieldFocused = true }
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
        .onTapGesture {
            withAnimation(.smooth(duration: 0.25)) { state = .expanded }
            // Defer focusing so the layout has time to settle.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                fieldFocused = true
            }
        }
    }

}
