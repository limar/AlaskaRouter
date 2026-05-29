// Human-readable display labels for place / waypoint categories.
//
// The places DB stores terse OSM-derived category keys ("settlement_major",
// "fuel", "river_crossing", …). The UI should never surface those raw — they
// read as cryptic jargon ("settlement major"). This is the single source of
// truth for the friendly label shown in the bottom sheet, the stop/preview
// callouts, and the search-results rows.
//
// Search the other direction (user types "town"/"city"/"gas" → category) lives
// in QueryParser.categoryPhrases.

import Foundation

enum CategoryLabel {

    /// Friendly labels for the known category keys. Anything not listed falls
    /// back to a title-cased, underscore-spaced rendering.
    private static let map: [String: String] = [
        "settlement":       "Town",
        "settlement_major": "City",
        "fuel":             "Gas",
        "peak":             "Peak",
        "glacier":          "Glacier",
        "spring":           "Spring",
        "waterfall":        "Waterfall",
        "airfield":         "Airport",
        "lighthouse":       "Lighthouse",
        "visitor_center":   "Visitor center",
        "ranger_station":   "Ranger station",
        "river_crossing":   "River crossing",
        "post":             "Post office",
        "camping":          "Campground",
        "hut":              "Hut",
        "lodging":          "Lodging",
        "viewpoint":        "Viewpoint",
        "pharmacy":         "Pharmacy",
        "medical":          "Medical",
        "food":             "Restaurant",
        "store":            "Store",
        "bank":             "Bank",
        "volcano":          "Volcano",
        "historic":         "Historic site",
    ]

    /// Display label for a raw category key. `nil`/empty → "Stop". Unknown keys
    /// are title-cased with underscores turned into spaces (e.g. "foo_bar" →
    /// "Foo Bar") so a new OSM category never shows an underscore.
    static func display(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Stop" }
        if let friendly = map[raw] { return friendly }
        return raw
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
