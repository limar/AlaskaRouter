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

    /// Tracks which `placeMarkerStyle` value the current MapLibre image
    /// cache holds, so the ExpeditionMapView hook can detect a Tweak flip
    /// and re-register every icon. -1 = "never registered yet".
    /// MainActor-isolated because the registration site is on the main
    /// queue and the Tweaks panel mutates from MainActor too.
    @MainActor static var lastRegisteredStyle: Int = -1

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

    /// Render the marker bitmap for a category, using the visual style
    /// currently selected in the TweaksStore A/B harness. Returns nil for
    /// areal categories (those should not carry an icon).
    @MainActor
    static func image(for category: String) -> UIImage? {
        guard let shape = shape(for: category) else { return nil }
        let color = color(for: category)
        return render(shape: shape, color: color, style: TweaksStore.shared.placeMarkerStyle)
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

    /// Render a marker using the selected visual style (spike harness):
    ///   0 — filled (iteration 3): saturated 16×16 colored shape
    ///   1 — outline + cream halo: stroke-only color over a wider cream
    ///       halo path, baked into a 16×16 bitmap
    ///   2 — smaller + translucent: 16×16 canvas, shape inset further +
    ///       alpha 0.6
    private static func render(shape: PlaceShape, color: UIColor, style: Int) -> UIImage {
        let size: CGFloat = 16
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            switch style {
            case 1: renderOutlineHalo(shape: shape, color: color, size: size)
            case 2: renderTranslucent(shape: shape, color: color, size: size)
            default: renderFilled(shape: shape, color: color, size: size)
            }
        }
    }

    /// Variant 0 — iteration-3 baseline. Saturated filled colored shape.
    private static func renderFilled(shape: PlaceShape, color: UIColor, size: CGFloat) {
        color.setFill()
        path(for: shape, in: size).fill()
    }

    /// Variant 2 — smaller (extra inset) + translucent (alpha 0.6).
    private static func renderTranslucent(shape: PlaceShape, color: UIColor, size: CGFloat) {
        color.withAlphaComponent(0.6).setFill()
        // Shrink the shape by re-rendering with a smaller "virtual" size centered.
        // Quickest: just apply an extra inset by drawing into a smaller rect.
        let inner: CGFloat = 10
        let off = (size - inner) / 2
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()
        ctx?.translateBy(x: off, y: off)
        path(for: shape, in: inner).fill()
        ctx?.restoreGState()
    }

    /// Variant 1 — outline shape on a cream halo. Visually coherent with the
    /// labels (which carry the same cream halo treatment). Drawn as: a wider
    /// cream stroke layer first, then a thinner colored stroke on top.
    /// Shapes are *not filled* — the interior is transparent so the basemap
    /// shows through, lightening the visual weight.
    private static func renderOutlineHalo(shape: PlaceShape, color: UIColor, size: CGFloat) {
        let cream = UIColor(red: 1.0, green: 250/255, blue: 238/255, alpha: 0.92)
        // Slightly smaller shape to leave room for the halo stroke.
        let inner: CGFloat = 12
        let off = (size - inner) / 2
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.saveGState()
        ctx?.translateBy(x: off, y: off)
        let p = path(for: shape, in: inner)
        // Round joins/caps for a friendlier hand-drawn feel.
        p.lineJoinStyle = .round
        p.lineCapStyle = .round
        // Cream halo first (wider).
        cream.setStroke()
        p.lineWidth = 3.0
        p.stroke()
        // Colored thin stroke on top.
        color.setStroke()
        p.lineWidth = 1.4
        p.stroke()
        ctx?.restoreGState()
    }

    /// Pure-geometry path builder for the four shapes, drawn inside an
    /// `inner × inner` square at origin (0, 0). Caller transforms or
    /// strokes/fills as needed.
    private static func path(for shape: PlaceShape, in inner: CGFloat) -> UIBezierPath {
        let rect = CGRect(x: 0, y: 0, width: inner, height: inner)
        switch shape {
        case .triangle:
            let inset: CGFloat = 1.0
            let p = UIBezierPath()
            p.move(to:    CGPoint(x: inner / 2,         y: inset))
            p.addLine(to: CGPoint(x: inner - inset,     y: inner - inset))
            p.addLine(to: CGPoint(x: inset,             y: inner - inset))
            p.close()
            return p
        case .square:
            let inset: CGFloat = 2.0
            return UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                                cornerRadius: 1.2)
        case .cross:
            let armLen: CGFloat = inner / 2 - 1.5
            let armWidth: CGFloat = 2.2
            let cx = inner / 2, cy = inner / 2
            // Compose horizontal + vertical bars into a single path
            // (matters for the outline variant which strokes the path).
            let p = UIBezierPath(rect: CGRect(
                x: cx - armLen, y: cy - armWidth / 2,
                width: armLen * 2, height: armWidth))
            p.append(UIBezierPath(rect: CGRect(
                x: cx - armWidth / 2, y: cy - armLen,
                width: armWidth, height: armLen * 2)))
            return p
        case .dot:
            let inset: CGFloat = 3.5
            return UIBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))
        }
    }
}
