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
