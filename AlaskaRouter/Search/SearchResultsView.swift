// Search-results dropdown rendered under the expanded floating bar.
//
// Each row has two tap targets:
//   - Body  → `onPreview(result)`   (research-first, opens floating callout)
//   - "+"   → `onFastAdd(result)`   (instant geographic-smart insert into trip)

import SwiftUI
import CoreLocation

struct SearchResultsView: View {
    let results: [SearchResult]
    let parsed: StructuredQuery
    let onPreview: (SearchResult) -> Void
    let onFastAdd: (SearchResult) -> Void

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
                resultRow(result)
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
    private func resultRow(_ result: SearchResult) -> some View {
        HStack(spacing: 12) {
            // Tappable body — opens preview.
            Button { onPreview(result) } label: {
                HStack(spacing: 12) {
                    iconForCategory(result.category)
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        // Replaced the lat/lon line with admin-area context
                        // (AlaskaRouter-b7g0): "category · Denali, AK, USA"
                        // (or "AK, USA" when admin_area is empty — universal
                        // fallback that still disambiguates from adjacent
                        // Canada when the v2+ multi-region work lands).
                        HStack(spacing: 4) {
                            Text(result.category.replacingOccurrences(of: "_", with: " "))
                            Text("·")
                            Text(locationLine(for: result))
                            if result.stage == SearchStage.editDistance.rawValue {
                                Text("·").foregroundStyle(.secondary)
                                Text("fuzzy ±\(result.editDistance)")
                                    .foregroundStyle(.orange.opacity(0.9))
                            } else if result.stage == SearchStage.synonyms.rawValue {
                                Text("·").foregroundStyle(.secondary)
                                Text("synonym")
                                    .foregroundStyle(.orange.opacity(0.9))
                            } else if result.stage == SearchStage.droppedTokens.rawValue {
                                Text("·").foregroundStyle(.secondary)
                                Text("loose")
                                    .foregroundStyle(.orange.opacity(0.9))
                            }
                        }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Trailing "+" — fast-add (instant geographic-smart insert).
            // Palette rendering (AlaskaRouter-yxve): the inner `+` is an
            // explicit WHITE layer, not a cutout — otherwise in dark mode
            // it shows the dark sheet through the cutout and looks empty.
            Button { onFastAdd(result) } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, SheetPalette.accentWarm)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// "Denali, AK, USA" when adminArea is non-empty; "AK, USA" otherwise.
    /// The state+country suffix is universal in v1 (everything is Alaska),
    /// but kept visible so users disambiguate v.s. adjacent Canada — many
    /// toponyms (Yukon River, etc.) repeat across the border. When v2+
    /// multi-region lands, this is where country/state derivation hooks in.
    /// AlaskaRouter-b7g0.
    private func locationLine(for r: SearchResult) -> String {
        if r.adminArea.isEmpty { return "AK, USA" }
        return "\(r.adminArea), AK, USA"
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
