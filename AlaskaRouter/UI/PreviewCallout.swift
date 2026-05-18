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
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                categoryIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(result.category.replacingOccurrences(of: "_", with: " "))
                        Text("·")
                        Text(String(format: "%.3f, %.3f",
                                    result.coord.latitude,
                                    result.coord.longitude))
                    }
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

            if let d = distanceFromTripText {
                Text(d)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
            }

            Button(action: onAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add to trip")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color(red: 0.78, green: 0.32, blue: 0.20), in: Capsule())
            }
            .buttonStyle(.plain)
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
        Image(systemName: sfSymbol(for: result.category))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color(red: 0.20, green: 0.40, blue: 0.65))
            .frame(width: 22, height: 22)
    }

    private func sfSymbol(for category: String) -> String {
        switch category {
        case "fuel":              return "fuelpump.fill"
        case "camping":           return "tent.fill"
        case "visitor_center":    return "info.circle.fill"
        case "ranger_station":    return "shield.lefthalf.filled"
        case "lodging":           return "bed.double.fill"
        case "settlement",
             "settlement_major":  return "house.fill"
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
