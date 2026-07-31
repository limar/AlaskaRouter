// Floating callout shown when a trip waypoint is selected (via map tap or
// bottom-sheet tap). Follows the design-handoff mock's POI callout pattern,
// trimmed for the v1 essentials and with a horizontal action toolbar at the
// bottom — navigation (prev/next), reorder (up/down), and remove. The toolbar
// replaces the earlier external chevrons + big Remove button to keep the
// callout compact and to put all per-stop actions in one obvious place.

import SwiftUI
import CoreLocation

struct StopCallout: View {
    let waypoint: Waypoint
    let positionLabel: String              // "STOP 3 OF 5"
    let additionalPassNumbers: [Int]       // other 1-based stop indices visiting this coord (ykuf step 4)
    let distanceFromPrevText: String?      // "45 km from previous" (nil for stop 1)
    let distanceToNextText: String?        // "78 km to next" (nil for the last stop)
    let onShare: () -> Void
    let onClose: () -> Void
    let onRemove: () -> Void
    // NB: Prev/Next browsing was removed (AlaskaRouter-55pn) — the map *is* the
    // browser; people drag and follow the route ribbon rather than tap chevrons.
    // The action row is now LEFT = Remove (trip-membership slot), RIGHT = Share,
    // mirroring PreviewCallout's "Add to trip | Share" so Share is always the
    // trailing button. 'Move earlier / Move later' reorder is still parked under
    // AlaskaRouter-mhax (likely an on-map drag or route-aligned arrow labels).

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(positionLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    if let alsoLabel = alsoPassesLabel {
                        // Multi-pass disclosure: the same coord is revisited
                        // later in the trip. The map shows ONE marker per
                        // coord (first-visit wins); this line surfaces the
                        // other passes so they're not invisible.
                        Text(alsoLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                    }
                    // firstTextBaseline, not centre: once CalloutTitle wraps a
                    // long name, a centred icon slides to the vertical middle
                    // of the block and stops reading as attached to it.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        CalloutIcon(category: waypoint.category, size: 12)
                        CalloutTitle(
                            text: waypoint.label ?? "Untitled stop",
                            size: 17,
                            weight: .semibold
                        )
                    }
                    // Category on its own line; distances grouped beneath as
                    // a visual pair (AlaskaRouter-wrso option 1).
                    Text(detailLine)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let prevLine = distanceFromPrevText {
                        Text(prevLine)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let nextLine = distanceToNextText {
                        Text(nextLine)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                // Removal lives here rather than in the action row: it is a
                // rare operation and does not deserve the most prominent slot
                // (AlaskaRouter-pmnd). Rename / Move-to-block can join it.
                Menu {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove from trip", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.4)

            // Single-row action band. The primary slot holds "Open in…" — a
            // constructive action worth putting under the thumb. Remove used
            // to live here as a ghost-red capsule and dominated the callout
            // (AlaskaRouter-pmnd); it now sits in the header "…" menu, which
            // is also where Rename / Move-to-block can go later.
            //
            // Vacating this slot without filling it was tried and rejected:
            // it leaves the row visibly empty beside a lone Share icon.
            Button(action: onShare) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Open in…")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                // Same warm fill and shape as PreviewCallout's "Add to trip",
                // so the two callouts carry one matching primary action.
                .background(SheetPalette.accentWarm, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // 260 → 300: the header "…" eats into the title's width, and at 260 it
        // truncated both the stop name and the "170 km from …" line. Still
        // under PreviewCallout's 320.
        .frame(maxWidth: 300)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
    }

    /// "ALSO STOP 9 · 12" (or "ALSO STOP 9" for a single revisit). Nil when
    /// the coord is only visited once.
    private var alsoPassesLabel: String? {
        guard !additionalPassNumbers.isEmpty else { return nil }
        let joined = additionalPassNumbers.map(String.init).joined(separator: " · ")
        return "ALSO STOP \(joined)"
    }

    private var detailLine: String {
        // Category only; the "from previous" and "to next" distances are now
        // their own lines beneath this one so the distance pair reads as a
        // group (AlaskaRouter-wrso).
        CategoryLabel.display(waypoint.category)
    }
}
