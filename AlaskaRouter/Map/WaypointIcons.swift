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

    static let committedDefault: UIImage = pngBacked(make(style: .committedDefault))
    static let committedSelected: UIImage = pngBacked(make(style: .committedSelected))
    static let preview: UIImage = pngBacked(make(style: .preview))

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
