// Floating callout shown when the user previews a search result without
// committing. Positioned in screen-space (not bottom-anchored) at roughly
// mid-screen — the map is flown to center on the pin, so the callout always
// reads as "the thing about this pin you're looking at." Apple Maps does the
// same trick for POI callouts.

import SwiftUI
import CoreLocation

struct PreviewCallout: View {
    let result: SearchResult
    let distanceFromTripText: String?       // e.g. "12 km from Healy", or nil if no trip
    let onAdd: () -> Void
    let onShare: () -> Void
    let onDismiss: () -> Void
    /// The active trip is read-only (AlaskaRouter-ijy9). "Add to trip" greys
    /// out rather than disappearing: the button vanishing would read as a bug,
    /// whereas a dimmed one says "not right now, and here is the button that
    /// would do it".
    var tripIsLocked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // firstTextBaseline so the category icon and the ✕ stay level with
            // the first line of the name rather than drifting to the middle
            // of a wrapped title (AlaskaRouter-dzhp).
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                categoryIcon
                VStack(alignment: .leading, spacing: 1) {
                    CalloutTitle(text: result.name, size: 16, weight: .bold)
                    // Friendly category label; lat/long dropped as useless —
                    // the admin-area line below gives location context
                    // (AlaskaRouter-tluk).
                    Text(CategoryLabel.display(result.category))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Admin-area line (AlaskaRouter-b7g0 / -5gmw / -4r8l). Same
            // "Borough, AK, USA" format the search-results dropdown uses.
            // "AK, USA" universal fallback when the admin-area lookup
            // returned nothing (rare — far ocean tap, or pre-load while
            // the donor index is still parsing in the background).
            Text(result.adminArea.isEmpty ? "AK, USA" : "\(result.adminArea), AK, USA")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 32)

            if let d = distanceFromTripText {
                Text(d)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }

            // Action row. LEFT slot = trip-membership action (Add to trip);
            // RIGHT slot = Share. The same left=membership / right=Share
            // spatial grammar is used in StopCallout (where the left slot is
            // "Remove"), so Share is always the trailing button across every
            // callout variant (AlaskaRouter-55pn).
            HStack(spacing: 8) {
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: tripIsLocked ? "lock.fill" : "plus.circle.fill")
                        Text("Add to trip")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        SheetPalette.accentWarm.opacity(tripIsLocked ? 0.35 : 1.0),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(tripIsLocked)
                .accessibilityHint(tripIsLocked ? "This trip is locked" : "")

                ShareCalloutButton(action: onShare)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 320)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }

    @ViewBuilder
    private var categoryIcon: some View {
        CalloutIcon(category: result.category, size: 18)
            .frame(width: 22, height: 22)
    }
}
