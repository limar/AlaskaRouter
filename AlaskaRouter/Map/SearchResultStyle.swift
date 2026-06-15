// Visual style for group-search result dots (AlaskaRouter-unir).
//
// Results render as a single generic, strongly-colored circle (disc + white
// stroke, zoom-scaled radius) — deliberately NOT the per-category POI glyph,
// so a set of results reads as one homogeneous "here are your matches" layer
// that pops above the ambient category icons. The fill color is a curated
// palette indexed by TweaksStore.searchResultColor so it can be tuned live.

import UIKit
import SwiftUI

enum SearchResultStyle {

    /// Curated strong colors. Index 0 is the default (a vivid electric blue —
    /// the preview/dropped pin's slate-blue, but turned up so it isn't shy on
    /// the vibrant basemap). The rest give live A/B options in the Tweaks panel.
    static let palette: [(name: String, color: UIColor)] = [
        ("Electric blue", UIColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 1)),
        ("Tomato",        UIColor(red: 0.90, green: 0.22, blue: 0.18, alpha: 1)),
        ("Vivid orange",  UIColor(red: 0.96, green: 0.45, blue: 0.10, alpha: 1)),
        ("Magenta",       UIColor(red: 0.85, green: 0.15, blue: 0.55, alpha: 1)),
        ("Violet",        UIColor(red: 0.52, green: 0.20, blue: 0.86, alpha: 1)),
        ("Emerald",       UIColor(red: 0.10, green: 0.62, blue: 0.36, alpha: 1)),
    ]

    static var count: Int { palette.count }

    static func uiColor(for index: Int) -> UIColor {
        guard palette.indices.contains(index) else { return palette[0].color }
        return palette[index].color
    }

    static func name(for index: Int) -> String {
        guard palette.indices.contains(index) else { return palette[0].name }
        return palette[index].name
    }

    /// SwiftUI accessor for the Tweaks panel swatches.
    static func color(for index: Int) -> Color { Color(uiColor: uiColor(for: index)) }
}
