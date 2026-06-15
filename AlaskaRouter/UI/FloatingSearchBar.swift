// Floating search bar — pill collapse aesthetic (locked v1, 2026-05-18).
//
// Two states:
//   - .expanded:  full Safari-style pill with search field, clear-x (when
//                  there's text), and a trailing Cancel button. Cancel is
//                  ALWAYS present while expanded — it's the dismiss
//                  affordance, so it must not depend on keyboard focus.
//                  Tap Cancel to dismiss search entirely; tap clear-x to
//                  wipe the query but keep typing.
//   - .collapsed: thin oval pill below the Dynamic Island, showing the active
//                  trip name + chevron. Tap to re-expand.
//
// Expand/collapse + Cancel visibility follow one rule (SearchBarRule, see
// bottom of file): the bar is expanded while "search is active" (field
// focused OR a non-empty query) and collapsed otherwise; Cancel shows
// whenever the bar is expanded. Gating Cancel on keyboard focus instead was
// the th0e regression — Cancel vanished (reverting to a decorative AK chip)
// the moment the field blurred while a query remained (hit Return, or the
// interactive scroll-to-dismiss on the results list), stranding the user
// with no way back to the map.
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
    /// y7l0 — invoked when the user taps the Cancel button (replaces the AK
    /// chip while the field is focused). RootView wires this to
    /// `dismissSearch()`. Optional so a unit-test instance can omit it.
    var onCancel: (() -> Void)? = nil
    /// AlaskaRouter-unir — invoked when the user commits the query from the
    /// keyboard (Return / the .search submit key). RootView wires this to
    /// promote the typed query into a nearest-N group search rendered on the
    /// map. Tapping an individual result ROW stays the single-pick path.
    var onSubmit: (() -> Void)? = nil

    /// Reactive read of the TweaksStore so the bar re-renders when the user
    /// flips the Cancel button style/color/weight from the Tweaks panel.
    @State private var tweaks = TweaksStore.shared

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
                .onSubmit { onSubmit?() }
                // Place names (Native, Russian, Athabaskan transliterations
                // like "Kotsina") aren't English words; autocorrect mangles
                // them mid-type. Disable correction + capitalization + spell.
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .keyboardType(.default)
            // Clear button (AlaskaRouter-7i4o) — only visible when there's
            // text to clear. Tapping it empties the field and keeps focus
            // so the user can immediately keep typing.
            if !query.isEmpty {
                Button {
                    query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            // Trailing affordance: Cancel, always present while expanded
            // (th0e). Cancel is the user-facing dismissal affordance — never
            // an icon, to avoid the two-x antipattern (clear-x for query vs
            // dismiss-x for search). It must NOT be gated on keyboard focus:
            // the field blurs on Return and on interactive scroll-to-dismiss
            // of the results list, and the user still needs a way out.
            // (The old focus-blurred state showed a decorative "AK" region
            // chip here; retired in th0e — it had no function and stole the
            // dismiss affordance. A region indicator can return elsewhere
            // when it becomes tappable.)
            cancelButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .contentShape(Capsule())
        .onTapGesture { fieldFocused = true }
    }

    // MARK: - Trailing affordance (y7l0 spike → th0e: always Cancel)

    /// Cancel button. Three visual variants × six colors × five font weights,
    /// all driven by TweaksStore — see y7l0 spike. Generous invisible
    /// hit-padding so the right-edge button isn't easy to thumb-miss.
    private var cancelButton: some View {
        Button {
            onCancel?()
        } label: {
            Group {
                switch tweaks.cancelButtonStyle {
                case 0:  plainTextCancel
                case 1:  filledChipCancel
                case 2:  outlinedChipCancel
                default: plainTextCancel
                }
            }
            // Invisible hit-padding for thumb-comfort.
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Reads tweaks each render so live A/B works without a tap-blur cycle.
        .id("cancel-\(tweaks.cancelButtonStyle)-\(tweaks.cancelButtonColor)-\(tweaks.cancelButtonFontWeight)")
    }

    private var plainTextCancel: some View {
        Text("Cancel")
            .font(.system(size: 15, weight: swiftUIFontWeight(tweaks.cancelButtonFontWeight)))
            .foregroundStyle(cancelPaletteColor(tweaks.cancelButtonColor))
    }

    private var filledChipCancel: some View {
        Text("Cancel")
            .font(.system(size: 13, weight: swiftUIFontWeight(tweaks.cancelButtonFontWeight)))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(cancelPaletteColor(tweaks.cancelButtonColor), in: Capsule(style: .continuous))
    }

    private var outlinedChipCancel: some View {
        Text("Cancel")
            .font(.system(size: 13, weight: swiftUIFontWeight(tweaks.cancelButtonFontWeight)))
            .foregroundStyle(cancelPaletteColor(tweaks.cancelButtonColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(cancelPaletteColor(tweaks.cancelButtonColor), lineWidth: 1)
            )
    }

    /// 7-color Cancel palette (matches TweaksStore docs).
    private func cancelPaletteColor(_ idx: Int) -> Color {
        switch idx {
        case 0:  return Color(red: 0.35, green: 0.45, blue: 0.55)   // slate blue
        case 1:  return Color(red: 0.20, green: 0.40, blue: 0.65)   // brand blue
        case 2:  return .blue                                        // system blue
        case 3:  return Color(red: 0.30, green: 0.30, blue: 0.30)   // charcoal
        case 4:  return Color(white: 0.55)                           // secondary gray
        case 5:  return Color(red: 0.20, green: 0.55, blue: 0.55)   // teal
        case 6:  return .red                                         // system red (zaha)
        default: return Color(red: 0.35, green: 0.45, blue: 0.55)
        }
    }

    private func swiftUIFontWeight(_ idx: Int) -> Font.Weight {
        switch idx {
        case 0:  return .regular
        case 1:  return .medium
        case 2:  return .semibold
        case 3:  return .bold
        case 4:  return .heavy
        default: return .semibold
        }
    }

    private var collapsedPill: some View {
        // (unir) The collapsed pill is a SEARCH affordance, not a trip-name
        // readout. The old prominent black trip name didn't help anything in
        // the search bar and read as a heavy label; replaced with a light-grey
        // "Search…" placeholder, mirroring a resting search field.
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Search…")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
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

/// Pure decision rules for the floating search bar's collapse/expand state
/// and its dismiss affordance. Extracted from the view (th0e) so the rule
/// set is unit-testable without driving SwiftUI.
///
/// Single source of truth: **search is active** when the field is focused
/// OR there is a non-empty query. The bar is expanded while search is
/// active and collapsed otherwise; Cancel shows whenever the bar is
/// expanded. Keeping these derived from one predicate is what prevents the
/// bar from getting stuck expanded after the field blurs (the th0e bug).
enum SearchBarRule {
    /// Whether the user is currently in "search mode".
    static func isSearchActive(fieldFocused: Bool, query: String) -> Bool {
        fieldFocused || !query.isEmpty
    }

    /// The bar's resting state for a given search-active condition.
    static func restingState(searchActive: Bool) -> FloatingSearchBarState {
        searchActive ? .expanded : .collapsed
    }

    /// Whether the Cancel (dismiss) affordance is shown. Cancel is available
    /// whenever the bar is expanded — explicitly NOT gated on keyboard focus,
    /// which was the th0e regression: Cancel disappeared after Return / a
    /// results-list scroll blurred the field while a query remained.
    static func showsCancel(state: FloatingSearchBarState) -> Bool {
        state == .expanded
    }
}
