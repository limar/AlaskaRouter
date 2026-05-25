// Small monochrome map markers for the places overlay (AlaskaRouter-vyfe).
//
// Four geometric shapes — triangle, square, cross, dot — each in a category-
// specific warm color, baked at runtime via CoreGraphics. Registered with the
// MapLibre style under `place-<category>` names; the style-base.json layers
// reference them via an icon-image match expression on the feature's category.
//
// Design intent (from user feedback after the first vyfe iteration):
//   "small and monochromatic (like those black mini-triangles for mountain
//    peaks). A color and a small geometrical form. Labels actually are doing
//    a great job of explaining what it is."
//
// "Areal" categories (glacier, park, lake, island, waterfall) intentionally
// have NO icon — they're visually identifiable on the OpenTopoMap raster, and
// adding a marker on a 50 km² lake would be confusing. For those, the label
// alone is the tap target (anchored at the centroid).
//
// MapLibre symbol-layer collision treats icon+text as one unit by default:
// if either part can't place (text-optional=false, icon-optional=false), the
// whole symbol is dropped. That gives us the "icon and label appear or
// disappear together" guarantee the user asked for.

import UIKit

enum PlaceShape {
    case triangle
    case square
    case cross
    case dot
}

enum PlaceIcons {

    // MARK: - Public API

    /// All categories that should get a rendered marker. Areal categories
    /// (glacier, park, lake, island, waterfall) are intentionally omitted —
    /// they're label-only on the map.
    static let iconedCategories: [String] = [
        "peak",
        "settlement_major", "settlement",
        "airfield",
        "fuel", "food", "lodging", "camping",
        "visitor_center", "ranger_station",
        "viewpoint", "attraction", "marina",
        "volcano",
        "hut", "spring", "cave", "water", "services",
        "bank", "post", "medical", "pharmacy",
        "store", "outdoor_shop", "vehicle_service", "hardware",
        "ev_charging", "river_crossing", "historic",
        "tower", "lighthouse", "picnic", "facilities",
        "locality", "parking",
    ]

    /// Marker name as referenced from style-base.json's icon-image match
    /// expression. Mirror this list in the style if changed.
    static func iconName(for category: String) -> String {
        "place-\(category)"
    }

    /// Render the marker bitmap for a category. Returns nil for areal
    /// categories (those should not carry an icon).
    static func image(for category: String) -> UIImage? {
        guard let shape = shape(for: category) else { return nil }
        let color = color(for: category)
        return render(shape: shape, color: color, size: 16)
    }

    // MARK: - Category → shape/color

    /// Areal categories return nil — label-only on the map.
    private static func shape(for category: String) -> PlaceShape? {
        switch category {
        case "peak":                                    return .triangle
        case "settlement_major", "settlement":          return .square
        case "airfield":                                return .cross
        case "glacier", "park", "lake", "island",
             "waterfall":                               return nil      // areal — no icon
        default:                                        return .dot
        }
    }

    /// Warm-paper palette colors mirroring the text-color match expressions
    /// in style-base.json so a feature's icon and label share a hue.
    private static func color(for category: String) -> UIColor {
        switch category {
        case "peak":                  return rgb(0x5A, 0x28, 0x18) // dark terracotta
        case "volcano":               return rgb(0x88, 0x30, 0x18) // red-orange
        case "settlement_major":      return rgb(0x3A, 0x2A, 0x18) // dark warm brown
        case "settlement":            return rgb(0x5A, 0x40, 0x30) // medium brown
        case "airfield":              return rgb(0x38, 0x40, 0x50) // slate
        case "fuel":                  return rgb(0x88, 0x30, 0x18) // red-orange
        case "ranger_station":        return rgb(0x1F, 0x40, 0x28) // forest green
        case "marina":                return rgb(0x1F, 0x38, 0x50) // deep blue
        case "viewpoint":             return rgb(0x70, 0x40, 0x18) // warm orange
        case "attraction",
             "visitor_center":        return rgb(0x70, 0x52, 0x18) // amber
        case "lighthouse":            return rgb(0x70, 0x52, 0x18) // amber
        case "historic":              return rgb(0x6A, 0x4A, 0x2A) // sepia
        case "medical",
             "pharmacy":              return rgb(0x88, 0x30, 0x30) // medical red
        case "ev_charging":           return rgb(0x28, 0x55, 0x28) // green
        default:                      return rgb(0x3A, 0x2A, 0x18) // warm brown default
        }
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1.0)
    }

    // MARK: - Render

    /// Draw a single 16×16 marker centered in its bitmap. Designed to read
    /// at MapLibre's default icon-size 1.0 against the warm OpenTopoMap
    /// basemap. Small inset on every shape keeps a thin transparent ring
    /// around the glyph so neighboring markers don't bleed together.
    private static func render(shape: PlaceShape, color: UIColor, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            color.setFill()
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            switch shape {
            case .triangle:
                // ▲ filled equilateral triangle, point up. Inset 1.5 px so the
                // shape sits inside the 16-px canvas with breathing room.
                let inset: CGFloat = 1.5
                let path = UIBezierPath()
                path.move(to:    CGPoint(x: size / 2,          y: inset))
                path.addLine(to: CGPoint(x: size - inset,      y: size - inset))
                path.addLine(to: CGPoint(x: inset,             y: size - inset))
                path.close()
                path.fill()
            case .square:
                // ■ filled rounded square.
                let inset: CGFloat = 3.0
                UIBezierPath(
                    roundedRect: rect.insetBy(dx: inset, dy: inset),
                    cornerRadius: 1.2
                ).fill()
            case .cross:
                // + bold plus sign — for airfields ("crossroads in the sky").
                let armLen: CGFloat   = 5.0
                let armWidth: CGFloat = 2.6
                let cx = size / 2, cy = size / 2
                UIBezierPath(rect: CGRect(
                    x: cx - armLen,     y: cy - armWidth / 2,
                    width: armLen * 2,  height: armWidth)
                ).fill()
                UIBezierPath(rect: CGRect(
                    x: cx - armWidth / 2, y: cy - armLen,
                    width: armWidth,      height: armLen * 2)
                ).fill()
            case .dot:
                // ● small filled circle.
                let inset: CGFloat = 4.5
                UIBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset)).fill()
            }
        }
    }
}
