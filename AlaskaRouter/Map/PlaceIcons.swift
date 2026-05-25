// Place-marker icons rendered via SF Symbols (AlaskaRouter-vyfe iteration 5).
//
// Categories map to an SF Symbol (e.g. peak → mountain.2.fill, airfield →
// airplane, fuel → fuelpump.fill, ranger_station → shield.lefthalf.filled,
// volcano → flame.fill, viewpoint → binoculars.fill, settlement → house.fill).
// Each symbol gets baked into a 22×22 bitmap and registered with MapLibre's
// style.setImage(_:forName:) under "place-<category>".
//
// Four visual variants behind a TweaksStore A/B picker:
//   0 — Filled (saturated, no halo)              — baseline / heavy
//   1 — Outline + cream halo (CANDIDATE)         — outline SF + cream rim
//   2 — Translucent, no halo                     — filled SF @ 0.65 alpha
//   3 — Translucent + cream halo                 — filled SF @ 0.65 alpha + rim
//
// Halo is implemented via CGContext.setShadow(offset:zero, blur, color: cream),
// which puts a soft cream rim around every non-transparent pixel of the glyph.
//
// Areal categories (glacier, park, lake, island, waterfall) return nil from
// `image(for:)` — those features remain label-only on the map, since they're
// visually identifiable from the basemap shape itself.

import UIKit

enum PlaceIcons {

    /// Tracks which `placeMarkerStyle` value the current MapLibre image
    /// cache holds, so the ExpeditionMapView hook can detect a Tweak flip
    /// and re-register every icon. -1 = "never registered yet".
    /// MainActor-isolated because the registration site is on the main
    /// queue and the Tweaks panel mutates from MainActor too.
    @MainActor static var lastRegisteredStyle: Int = -1

    // MARK: - Public API

    /// All point categories that get a rendered marker. Areal categories
    /// (glacier, park, lake, island, waterfall) are intentionally omitted —
    /// they're label-only on the map.
    static let iconedCategories: [String] = [
        // Settlements / habitation
        "settlement_major", "settlement", "locality", "hut",
        // Air / boats / vehicles
        "airfield", "marina",
        // Energy / services
        "fuel", "ev_charging", "vehicle_service",
        // Hospitality / amenities
        "food", "lodging", "camping", "picnic",
        // Civic / info
        "visitor_center", "ranger_station", "post", "bank",
        // Health
        "medical", "pharmacy",
        // Shopping
        "store", "outdoor_shop", "hardware",
        // Sights / scenery
        "viewpoint", "attraction", "historic", "lighthouse",
        // Natural points
        "peak", "volcano", "spring", "cave", "water",
        // Infrastructure
        "tower", "river_crossing", "services", "facilities", "parking",
    ]

    /// Marker name as referenced from style-base.json's icon-image match
    /// expression.
    static func iconName(for category: String) -> String {
        "place-\(category)"
    }

    /// Render the marker bitmap for a category, using the visual style
    /// currently selected in the TweaksStore A/B harness. Returns nil for
    /// areal categories (those should not carry an icon).
    @MainActor
    static func image(for category: String) -> UIImage? {
        guard isPointCategory(category) else { return nil }
        let color = color(for: category)
        return render(
            category: category,
            color: color,
            style: TweaksStore.shared.placeMarkerStyle
        )
    }

    // MARK: - Category classification + colors

    /// Areal categories don't get an icon — only a label centered on the centroid.
    private static func isPointCategory(_ category: String) -> Bool {
        switch category {
        case "glacier", "park", "lake", "island", "waterfall":  return false
        default:                                                return true
        }
    }

    /// Warm-paper palette mirroring the text-color match expressions in
    /// style-base.json so a feature's icon and label share a hue.
    private static func color(for category: String) -> UIColor {
        switch category {
        case "peak":                  return rgb(0x5A, 0x28, 0x18) // dark terracotta
        case "volcano":               return rgb(0x88, 0x30, 0x18) // red-orange
        case "settlement_major":      return rgb(0x3A, 0x2A, 0x18) // dark warm brown
        case "settlement", "locality", "hut": return rgb(0x5A, 0x40, 0x30) // medium brown
        case "airfield":              return rgb(0x38, 0x40, 0x50) // slate
        case "fuel":                  return rgb(0x88, 0x30, 0x18) // red-orange
        case "ev_charging":           return rgb(0x28, 0x55, 0x28) // green
        case "vehicle_service":       return rgb(0x38, 0x40, 0x50) // slate
        case "ranger_station":        return rgb(0x1F, 0x40, 0x28) // forest green
        case "marina":                return rgb(0x1F, 0x38, 0x50) // deep blue
        case "viewpoint":             return rgb(0x70, 0x40, 0x18) // warm orange
        case "attraction",
             "visitor_center",
             "historic",
             "lighthouse":            return rgb(0x70, 0x52, 0x18) // amber
        case "medical", "pharmacy":   return rgb(0x88, 0x30, 0x30) // medical red
        case "spring", "water",
             "river_crossing":       return rgb(0x2A, 0x52, 0x78) // water blue
        case "food", "picnic":        return rgb(0x6A, 0x38, 0x18) // food brown
        case "lodging":               return rgb(0x4A, 0x32, 0x22) // lodging brown
        case "camping":               return rgb(0x28, 0x55, 0x28) // tent green
        case "post", "bank":          return rgb(0x4A, 0x38, 0x28) // muted brown
        case "store", "outdoor_shop",
             "hardware":              return rgb(0x4A, 0x38, 0x28) // muted brown
        case "tower":                 return rgb(0x38, 0x40, 0x50) // slate
        default:                      return rgb(0x3A, 0x2A, 0x18) // warm brown default
        }
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1.0)
    }

    // MARK: - SF Symbol mapping

    /// Returns (filled-variant-name, outline-variant-name) for a category.
    /// SF Symbols where outline+fill are the same glyph (e.g. `airplane`)
    /// return the same name in both slots.
    private static func sfSymbol(for category: String) -> (filled: String, outline: String) {
        switch category {
        case "settlement_major":   return ("building.2.fill",        "building.2")
        case "settlement":         return ("house.fill",             "house")
        case "locality", "hut":    return ("house.fill",             "house")
        case "airfield":           return ("airplane",               "airplane")
        case "marina":             return ("ferry.fill",             "ferry")
        case "fuel":               return ("fuelpump.fill",          "fuelpump")
        case "ev_charging":        return ("bolt.fill",              "bolt")
        case "vehicle_service":    return ("wrench.fill",            "wrench")
        case "food", "picnic":     return ("fork.knife",             "fork.knife")
        case "lodging":            return ("bed.double.fill",        "bed.double")
        case "camping":            return ("tent.fill",              "tent")
        case "visitor_center":     return ("info.circle.fill",       "info.circle")
        case "ranger_station":     return ("shield.lefthalf.filled", "shield")
        case "post":               return ("envelope.fill",          "envelope")
        case "bank":               return ("creditcard.fill",        "creditcard")
        case "medical":            return ("cross.case.fill",        "cross.case")
        case "pharmacy":           return ("pills.fill",             "pills")
        case "store":              return ("cart.fill",              "cart")
        case "outdoor_shop":       return ("mountain.2.fill",        "mountain.2")
        case "hardware":           return ("hammer.fill",            "hammer")
        case "viewpoint":          return ("binoculars.fill",        "binoculars")
        case "attraction":         return ("star.fill",              "star")
        case "historic":           return ("building.columns.fill",  "building.columns")
        case "lighthouse":         return ("lightbulb.fill",         "lightbulb")
        case "peak":               return ("triangle.fill",          "triangle")
        case "volcano":            return ("flame.fill",             "flame")
        case "spring", "water":    return ("drop.fill",              "drop")
        case "cave":               return ("circle.dotted",          "circle.dotted")
        case "tower":              return ("antenna.radiowaves.left.and.right",
                                            "antenna.radiowaves.left.and.right")
        case "river_crossing":     return ("water.waves",            "water.waves")
        case "services":           return ("wrench.fill",            "wrench")
        case "facilities":         return ("wrench.and.screwdriver.fill",
                                            "wrench.and.screwdriver")
        case "parking":            return ("parkingsign.circle.fill","parkingsign.circle")
        default:                   return ("mappin.circle.fill",     "mappin")
        }
    }

    // MARK: - Render

    /// Canvas + glyph sizes, tuned so peaks/houses/planes read clearly at
    /// MapLibre's icon-size 1.0 on a Retina display. Bumped from iter-3's
    /// 16×16 after user feedback: "the circle shape should be bigger,
    /// I hardly can see it."
    private static let canvas: CGFloat = 22
    private static let glyphPointSize: CGFloat = 14

    private static func render(category: String, color: UIColor, style: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas))
        return renderer.image { _ in
            switch style {
            case 1: renderGlyph(category: category, color: color, outline: true,  withHalo: true)
            case 2: renderGlyph(category: category, color: color.withAlphaComponent(0.65),
                                outline: false, withHalo: false)
            case 3: renderGlyph(category: category, color: color.withAlphaComponent(0.65),
                                outline: false, withHalo: true)
            default: renderGlyph(category: category, color: color, outline: false, withHalo: false)
            }
        }
    }

    /// Draw a single SF Symbol centered in the canvas.
    /// - `outline`: pick the outline variant of the symbol where one exists.
    /// - `withHalo`: surround the glyph with a soft cream rim via CGContext
    ///   shadow. Same cream color the labels use, so icon+label share a
    ///   visual treatment.
    private static func renderGlyph(category: String, color: UIColor, outline: Bool, withHalo: Bool) {
        let names = sfSymbol(for: category)
        let chosenName = outline ? names.outline : names.filled
        // Heavier weight on outline variants to compensate for the thinner
        // stroke; lighter on filled so the colored shape doesn't overwhelm.
        let weight: UIImage.SymbolWeight = outline ? .semibold : .regular
        let config = UIImage.SymbolConfiguration(pointSize: glyphPointSize, weight: weight)
        guard let baseSymbol = UIImage(systemName: chosenName, withConfiguration: config)
                ?? UIImage(systemName: names.filled, withConfiguration: config)
        else { return }
        let tinted = baseSymbol.withTintColor(color, renderingMode: .alwaysOriginal)

        let symW = tinted.size.width
        let symH = tinted.size.height
        let drawRect = CGRect(
            x: (canvas - symW) / 2,
            y: (canvas - symH) / 2,
            width: symW,
            height: symH
        )

        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        if withHalo {
            // Cream halo via shadow blur. Drawing the tinted symbol with this
            // shadow set lays down both: the cream blur around all alpha-
            // positive pixels, AND the symbol itself in its tinted color.
            // A 1.8-px blur reads as a thin halo at our 22-px canvas.
            let cream = UIColor(red: 1.0, green: 250/255, blue: 238/255, alpha: 0.95)
            ctx.setShadow(offset: .zero, blur: 1.8, color: cream.cgColor)
        }
        tinted.draw(in: drawRect)
    }
}
