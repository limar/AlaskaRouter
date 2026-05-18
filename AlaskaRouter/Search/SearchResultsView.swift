// Search-results dropdown rendered under the expanded floating bar.

import SwiftUI
import CoreLocation

struct SearchResultsView: View {
    let results: [SearchResult]
    let parsed: StructuredQuery
    let onSelect: (SearchResult) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !parsed.categoryHints.isEmpty {
                HStack(spacing: 6) {
                    ForEach(parsed.categoryHints, id: \.self) { hint in
                        Text(hint.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.orange)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            ForEach(results) { result in
                Button { onSelect(result) } label: {
                    HStack(spacing: 12) {
                        iconForCategory(result.category)
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(result.category.replacingOccurrences(of: "_", with: " "))
                                Text("·")
                                Text(String(format: "%.3f, %.3f",
                                            result.coord.latitude,
                                            result.coord.longitude))
                                if result.stage == 2 {
                                    Text("·").foregroundStyle(.secondary)
                                    Text("fuzzy ±\(result.editDistance)")
                                        .foregroundStyle(.orange.opacity(0.9))
                                }
                            }
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.4)
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

    @ViewBuilder
    private func iconForCategory(_ category: String) -> some View {
        switch category {
        case "fuel":              Image(systemName: "fuelpump.fill")
        case "camping":           Image(systemName: "tent.fill")
        case "visitor_center":    Image(systemName: "info.circle.fill")
        case "ranger_station":    Image(systemName: "shield.lefthalf.filled")
        case "lodging":           Image(systemName: "bed.double.fill")
        case "settlement",
             "settlement_major":  Image(systemName: "house.fill")
        case "peak":              Image(systemName: "mountain.2.fill")
        case "glacier":           Image(systemName: "snowflake")
        case "river_crossing":    Image(systemName: "water.waves")
        case "viewpoint":         Image(systemName: "binoculars.fill")
        case "airfield":          Image(systemName: "airplane")
        case "food":              Image(systemName: "fork.knife")
        case "store":             Image(systemName: "cart.fill")
        case "medical":           Image(systemName: "cross.case.fill")
        case "spring":            Image(systemName: "drop.fill")
        case "waterfall":         Image(systemName: "drop.triangle.fill")
        case "hut":               Image(systemName: "house")
        case "volcano":           Image(systemName: "flame.fill")
        case "lighthouse":        Image(systemName: "lightbulb.fill")
        case "historic":          Image(systemName: "building.columns.fill")
        case "post":              Image(systemName: "envelope.fill")
        case "bank":              Image(systemName: "creditcard.fill")
        case "pharmacy":          Image(systemName: "pills.fill")
        case "parking":           Image(systemName: "parkingsign.circle.fill")
        default:                  Image(systemName: "mappin.circle.fill")
        }
    }
}
