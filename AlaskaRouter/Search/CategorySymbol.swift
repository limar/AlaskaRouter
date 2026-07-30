// SF Symbol names for place / waypoint categories, as used by the *UI chrome*
// — the stop callout, the preview callout, and the search-results rows.
//
// This existed as three byte-identical ~24-case switches (StopCallout,
// PreviewCallout, SearchResultsView). Three copies that must agree is how they
// stop agreeing, so this is now the single source of truth. It sits beside
// CategoryLabel, which already centralises the human-readable name for the
// same category keys.
//
// NB: `PlaceIcons` deliberately keeps its own, different mapping. That one
// drives the *map markers*, needs a filled/outline pair per category for its
// visual-variant harness, and makes different cartographic choices on purpose
// (peak → triangle, settlement → hollow circle, so markers read as an atlas
// rather than as a UI list). Merging the two would change what the map draws.

import Foundation

enum CategorySymbol {

    /// SF Symbol name for a raw category key. `nil` / unknown → a generic map
    /// pin, so a new OSM category always renders something.
    static func name(for category: String?) -> String {
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
