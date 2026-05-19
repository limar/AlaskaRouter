// Floating callout shown when a trip waypoint is selected (via map tap or
// bottom-sheet tap). Follows the design-handoff mock's POI callout pattern,
// trimmed for kcq8 essentials: identity + position + remove + prev/next.

import SwiftUI
import CoreLocation

struct StopCallout: View {
    let waypoint: Waypoint
    let positionLabel: String              // "STOP 3 OF 5"
    let distanceFromPrevText: String?      // "45 km from previous" (nil for stop 1)
    let canPrev: Bool
    let canNext: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            chevron(systemName: "chevron.left", enabled: canPrev, action: onPrev)
            body_card
            chevron(systemName: "chevron.right", enabled: canNext, action: onNext)
        }
        .padding(.horizontal, 4)
    }

    private var body_card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(positionLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    HStack(spacing: 6) {
                        Image(systemName: iconForCategory(waypoint.category))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(waypoint.label ?? "Untitled stop")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(detailLine)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Button(action: onRemove) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Remove from trip")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color(red: 0.78, green: 0.32, blue: 0.20), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
    }

    private func chevron(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? .primary : .tertiary)
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.45)
    }

    private var detailLine: String {
        let category = (waypoint.category ?? "stop").replacingOccurrences(of: "_", with: " ")
        if let d = distanceFromPrevText {
            return "\(category) · \(d)"
        }
        return category
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
