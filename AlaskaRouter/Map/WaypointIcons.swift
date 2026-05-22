// Programmatic waypoint icons. Three styles:
//   - `.committedDefault` — cream disc + brown ring + warm-tomato center, 44pt.
//   - `.committedSelected` — same palette, 60pt + stronger shadow + thicker ring.
//   - `.preview` — slate-blue disc + navy ring + light-blue center, 44pt. Used
//                  for the "investigating" pin while the user is previewing a
//                  search result (not yet added to the trip).

import UIKit

enum WaypointIconStyle {
    case committedDefault
    case committedSelected
    case preview
}

enum WaypointIcons {

    // New "Dot" silhouette (AlaskaRouter-ykuf). Solid color disc + 2pt white
    // stroke + subtle inner ring. The stop NUMBER is baked into the image
    // using UIKit's system-bold font — we can't get bold via MapLibre's
    // glyph stack today (only Noto Sans Regular is bundled — see
    // AlaskaRouter-ymw6). Baking gives us full typography control and
    // sidesteps that limitation.
    //
    // Cache: pre-rendered images keyed by "(selected, number, colorRGB)".
    // Trip waypoints register their needed images with the style and
    // reference them per-feature via the "iconKey" attribute.
    static let preview: UIImage = pngBacked(make(style: .preview))

    /// Lazy per-(number, selected, color) cache of rendered dots. Each
    /// distinct combo renders once and is reused across frames.
    /// Accessed only from the MainActor (via the unsafe hook), hence
    /// `nonisolated(unsafe)`.
    nonisolated(unsafe) private static var dotCache: [String: UIImage] = [:]

    /// Returns a Dot icon for the given stop number + block color +
    /// selected state, along with the stable image NAME used to register
    /// it with the map style. Reads sizes / typography from TweaksStore so
    /// live in-app tweaking can adjust the design without rebuilding.
    /// Cache key includes every tweak value — any change forces a fresh
    /// render and a fresh registered image.
    @MainActor
    static func dot(number: String, color: UIColor, selected: Bool) -> (image: UIImage, name: String) {
        let t = TweaksStore.shared
        let diameter: CGFloat = selected ? t.dotDiameterSelected : t.dotDiameterDefault
        let fontWeight = t.dotFontWeight
        let fontSizeRatio = t.dotFontSizeRatio

        // Color key + tweak fingerprint for stable cache key.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb = String(format: "%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
        let name = String(
            format: "dot-%@-%@-%@-d%d-w%d-s%d",
            selected ? "sel" : "def",
            number,
            rgb,
            Int(diameter),
            Int(fontWeight * 100),
            Int(fontSizeRatio * 100)
        )
        if let cached = dotCache[name] {
            return (cached, name)
        }
        let img = pngBacked(renderDotImage(
            diameter: diameter,
            color: color,
            number: number,
            fontWeight: fontWeight,
            fontSizeRatio: fontSizeRatio
        ))
        dotCache[name] = img
        return (img, name)
    }

    private static func renderDotImage(
        diameter: CGFloat,
        color: UIColor,
        number: String,
        fontWeight: Double,
        fontSizeRatio: Double
    ) -> UIImage {
        let pad: CGFloat = 4
        let size = diameter + 2 * pad
        let canvas = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { ctx in
            let c = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            let r = diameter / 2
            let strokeWidth: CGFloat = 2.0

            // Drop shadow under the disc.
            c.setShadow(offset: CGSize(width: 0, height: 1.2),
                        blur: 2.4,
                        color: UIColor.black.withAlphaComponent(0.22).cgColor)
            c.setFillColor(color.cgColor)
            c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            c.setShadow(offset: .zero, blur: 0, color: nil)

            // White outer stroke (inside the disc edge).
            c.setStrokeColor(UIColor.white.cgColor)
            c.setLineWidth(strokeWidth)
            let strokeRect = CGRect(
                x: center.x - r + strokeWidth / 2,
                y: center.y - r + strokeWidth / 2,
                width: r * 2 - strokeWidth,
                height: r * 2 - strokeWidth
            )
            c.strokeEllipse(in: strokeRect)

            // Faint inner ring for dimension hint (matches mock's 9.2/11 ratio).
            let innerR = r * 0.836
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            c.setLineWidth(0.7)
            c.strokeEllipse(in: CGRect(
                x: center.x - innerR, y: center.y - innerR,
                width: innerR * 2, height: innerR * 2
            ))

            // Digit, centered, with weight + size controlled by TweaksStore.
            // 2-digit numbers scale down by 0.76 of the 1-digit ratio so
            // "36" still fits without crowding the disc edges.
            let baseRatio = CGFloat(fontSizeRatio)
            let digitRatio: CGFloat = number.count >= 2 ? baseRatio * 0.76 : baseRatio
            let digitFontSize: CGFloat = diameter * digitRatio
            let font = UIFont.systemFont(
                ofSize: digitFontSize,
                weight: UIFont.Weight(rawValue: CGFloat(fontWeight))
            )
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                // Tabular numerics so "10" / "11" stay balanced on either
                // side of the icon's vertical axis.
                .kern: 0.0,
            ]
            let ns = number as NSString
            let textSize = ns.size(withAttributes: attrs)
            // Optical center-y nudges the digit up ~1pt because system
            // fonts have descender bias that visually drops the digit low.
            let textRect = CGRect(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2 - diameter * 0.03,
                width: textSize.width,
                height: textSize.height
            )
            ns.draw(in: textRect, withAttributes: attrs)
        }
    }

    /// Apple-Maps-style blue puck for the user's current location. 24pt halo
    /// + 14pt blue core with a thin white ring. Pixel-sized via iconImage()
    /// so it stays constant on the map across zooms (AlaskaRouter-j03u).
    static let userLocation: UIImage = pngBacked(makeUserLocation())

    private static func makeUserLocation() -> UIImage {
        let size: CGFloat = 28
        let canvas = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { ctx in
            let c = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            // Soft outer halo
            c.setShadow(offset: .zero, blur: 5,
                        color: UIColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 0.45).cgColor)
            c.setFillColor(UIColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 0.18).cgColor)
            c.fillEllipse(in: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
            c.setShadow(offset: .zero, blur: 0, color: nil)
            // White ring (outer)
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
            // Blue core
            c.setFillColor(UIColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 1.0).cgColor)
            c.fillEllipse(in: CGRect(x: center.x - 6.5, y: center.y - 6.5, width: 13, height: 13))
        }
    }

    /// `UIGraphicsImageRenderer` produces images whose `cgImage?.dataProvider?.data`
    /// is often unavailable (it's a render-target IOSurface, not raw bytes).
    /// MapLibreSwiftDSL keys icon registrations by `UIImage.sha256()`, which silently
    /// returns "" when `dataProvider.data` is nil — two such icons collide on name ""
    /// and the second clobbers the first in `style.setImage(_:forName:)`. Decoding
    /// through PNG guarantees a backing dataProvider with raw bytes, hence a unique hash.
    private static func pngBacked(_ image: UIImage) -> UIImage {
        guard let png = image.pngData(),
              let cg = UIImage(data: png)?.cgImage else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Render a "Dot" waypoint icon (AlaskaRouter-ykuf): solid-color disc +
    /// 2pt white stroke + faint inner ring at ~84% of the radius. Digit is
    /// rendered as a separate text layer; this image is just the silhouette.
    /// `diameter` is the visible outer-edge size in points.
    static func makeDot(diameter: CGFloat, color: UIColor) -> UIImage {
        // Pad the canvas so the stroke and shadow have breathing room.
        let pad: CGFloat = 4
        let size = diameter + 2 * pad
        let canvas = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { ctx in
            let c = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)
            let r = diameter / 2
            let strokeWidth: CGFloat = 2.0

            // Drop shadow under the disc.
            c.setShadow(offset: CGSize(width: 0, height: 1.2),
                        blur: 2.4,
                        color: UIColor.black.withAlphaComponent(0.22).cgColor)
            c.setFillColor(color.cgColor)
            c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            c.setShadow(offset: .zero, blur: 0, color: nil)

            // White outer stroke (sits inside the disc edge so it doesn't
            // bleed into the shadow).
            c.setStrokeColor(UIColor.white.cgColor)
            c.setLineWidth(strokeWidth)
            let strokeRect = CGRect(
                x: center.x - r + strokeWidth / 2,
                y: center.y - r + strokeWidth / 2,
                width: r * 2 - strokeWidth,
                height: r * 2 - strokeWidth
            )
            c.strokeEllipse(in: strokeRect)

            // Faint inner ring for hint of dimension (matches the mock's
            // 9.2/11 = 0.836 proportion).
            let innerR = r * 0.836
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            c.setLineWidth(0.7)
            c.strokeEllipse(in: CGRect(
                x: center.x - innerR, y: center.y - innerR,
                width: innerR * 2, height: innerR * 2
            ))
        }
    }

    private static func make(style: WaypointIconStyle) -> UIImage {
        let (size, ringWidth, shadowAlpha, shadowBlur, fillRGB, ringRGB, dotRGB): (CGFloat, CGFloat, CGFloat, CGFloat, (CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat)) = {
            switch style {
            case .committedDefault:
                return (44, 1.6, 0.22, 3,
                        (0.96, 0.93, 0.84),
                        (0.40, 0.30, 0.16),
                        (0.78, 0.32, 0.20))
            case .committedSelected:
                return (60, 2.2, 0.32, 6,
                        (0.99, 0.96, 0.86),
                        (0.78, 0.32, 0.20),
                        (0.78, 0.32, 0.20))
            case .preview:
                return (44, 1.6, 0.22, 3,
                        (0.83, 0.89, 0.95),
                        (0.20, 0.30, 0.48),
                        (0.20, 0.40, 0.65))
            }
        }()
        let canvas = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { ctx in
            let c = ctx.cgContext
            // Outer disc inset from edges so the shadow has room.
            let inset: CGFloat = max(4, size * 0.10)
            let disc = CGRect(x: inset, y: inset,
                              width: size - 2 * inset, height: size - 2 * inset)
            // Drop shadow on the fill stroke pair.
            c.setShadow(offset: CGSize(width: 0, height: size * 0.04),
                        blur: shadowBlur,
                        color: UIColor.black.withAlphaComponent(shadowAlpha).cgColor)
            c.setFillColor(UIColor(red: fillRGB.0, green: fillRGB.1, blue: fillRGB.2, alpha: 1.0).cgColor)
            c.fillEllipse(in: disc)
            c.setShadow(offset: .zero, blur: 0, color: nil)
            c.setStrokeColor(UIColor(red: ringRGB.0, green: ringRGB.1, blue: ringRGB.2, alpha: 0.95).cgColor)
            c.setLineWidth(ringWidth)
            c.strokeEllipse(in: disc.insetBy(dx: ringWidth * 0.5, dy: ringWidth * 0.5))
            // Center dot ~ 40% of the disc diameter.
            let dotInset = (disc.width * 0.30)
            c.setFillColor(UIColor(red: dotRGB.0, green: dotRGB.1, blue: dotRGB.2, alpha: 1.0).cgColor)
            c.fillEllipse(in: disc.insetBy(dx: dotInset, dy: dotInset))
        }
    }
}
