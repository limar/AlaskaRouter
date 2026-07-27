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
                    HStack(spacing: 6) {
                        Image(systemName: iconForCategory(waypoint.category))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(waypoint.label ?? "Untitled stop")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
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
                // Variant 1 (pmnd): Remove demoted into a header overflow
                // menu, leaving the action row free for things you actually
                // want to do. Room here for Rename / Move-to-block later.
                if LaunchArgs.removeVariant == 1 || LaunchArgs.removeVariant == 3 {
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
                }
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

            // Single-row action band (replaces the taller stacked-icon
            // toolbar). LEFT = Remove, styled ghost-red so a destructive
            // action sitting under the thumb doesn't carry the bold solid
            // weight of an "Add to trip" pill. RIGHT = Share, identical to the
            // PreviewCallout trailing button.
            HStack(spacing: 8) {
                // Variant 0 = today. Variants 1 and 2 both vacate this slot:
                // 1 moves Remove into the header menu, 2 drops it entirely and
                // relies on the stop row's own minus button, which already
                // exists (AlaskaRouter-0rh9) and is where the mock put removal.
                if LaunchArgs.removeVariant == 0 {
                    Button(action: onRemove) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Remove")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(SheetPalette.destructive)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(SheetPalette.destructive.opacity(0.12))
                        )
                        .overlay(
                            Capsule().stroke(SheetPalette.destructive.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    ShareCalloutButton(action: onShare)
                } else if LaunchArgs.removeVariant == 3 {
                    // Variants 1 and 2 vacate the primary slot and leave the
                    // action row visibly empty next to a lone Share icon. So
                    // promote Share into that slot instead: the callout keeps
                    // its shape, and the button under the thumb is now the
                    // action you actually want. Remove lives in the header "…".
                    Button(action: onShare) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Open in…")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer(minLength: 0)
                    ShareCalloutButton(action: onShare)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 260)
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

    private func iconForCategory(_ category: String?) -> String {
        switch category {
        case "fuel":              return "fuelpump.fill"
        case "camping":           return "tent.fill"
        case "visitor_center":    return "info.circle.fill"
        case "ranger_station":    return "shield.lefthalf.filled"
        case "lodging":           return "bed.double.fill"
        case "settlement",
             "settlement_major": return "house.fill"
        case "peak":              return "mountain.2.fill"
        case "glacier":           return "snowflake"
        case "river_crossing":    return "water.waves"
        case "viewpoint":         return "binoculars.fill"
        case "airfield":          return "airplane"
        case "food":              return "fork.knife"
        case "store":             return "cart.fill"
        case "medical":           return "cross.case.fill"
        case "spring":            return "drop.fill"
        case "waterfall":         return "drop.triangle.fill"
        case "hut":               return "house"
        case "volcano":           return "flame.fill"
        case "lighthouse":        return "lightbulb.fill"
        case "historic":          return "building.columns.fill"
        case "post":              return "envelope.fill"
        case "bank":              return "creditcard.fill"
        case "pharmacy":          return "pills.fill"
        case "parking":           return "parkingsign.circle.fill"
        default:                  return "mappin.circle.fill"
        }
    }
}
