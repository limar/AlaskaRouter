// Icons spike — isolate the "selected waypoint icon disappears" bug.
//
// Renders a 4×4 grid of markers near the equator using MapLibreSwiftDSL with
// different icon constellations chosen by the `-scenario` launch arg:
//   - all-default   : all 16 markers use icon A (44pt cream)
//   - all-selected  : all 16 markers use icon B (60pt cream + tomato ring)
//   - one-selected  : 15 use A in one source + 1 uses B in a second source
//                     (replicates the main-app bug condition)
//   - all-different : 16 markers, each a unique color (16 distinct UIImages
//                     across 16 separate ShapeSource/SymbolStyleLayer pairs)
//
// Each scenario prints a sha256-length diagnostic on launch so we can confirm
// every UIImage has a non-empty unique hash. Screenshot via:
//   xcrun simctl launch booted dev.alaskarouter.IconsSpike -scenario <name>
//   xcrun simctl io booted screenshot /tmp/icons-<name>.png

import SwiftUI
import MapLibre
import MapLibreSwiftUI
import MapLibreSwiftDSL
import CoreLocation
import CommonCrypto

@main
struct IconsSpikeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - Scenarios

enum Scenario: String {
    case allDefault       = "all-default"
    case allSelected      = "all-selected"
    case oneSelected      = "one-selected"
    case allDifferent     = "all-different"
    /// Same as one-selected but VERY distinct colors so wrong-icon vs no-icon
    /// is easy to distinguish at small render size (slot 7 uses palette[10] — vivid).
    case oneVivid         = "one-vivid"
    /// Reverse the layer-order: 1-feature selected source declared BEFORE the
    /// 15-feature default source. Does declaration order matter?
    case selectedFirst    = "selected-first"
    /// Two sources, both with a single feature, different icons. Does the bug
    /// disappear when neither source has > 1 feature?
    case twoSingles       = "two-singles"
    /// Two sources with 8 features each, different icons.
    case twoEqualSplit    = "two-equal-split"
    /// One source, 15 features, ALL using the SAME selected (palette[1]) icon
    /// — but in a SECOND source, 1 feature using palette[0]. Mirrors the bug
    /// with roles reversed.
    case oneSelectedFlip  = "one-selected-flip"
    /// 15 features in a DSL-managed source with default icon, AND 1 selected
    /// feature placed via RAW MLN APIs in onMapStyleLoaded (bypassing the DSL).
    case rawSelected      = "raw-selected"
    /// Zoom-in on slot 7 with the one-selected setup — at z=9 there's no
    /// ambiguity about what renders where.
    case zoomedOneSelected = "zoomed-one-selected"

    static var current: Scenario {
        let raw = UserDefaults.standard.string(forKey: "scenario") ?? "all-default"
        return Scenario(rawValue: raw) ?? .allDefault
    }
}

// MARK: - Icons

enum SpikeIcons {
    /// 16 candidate icons covering distinct colors. iconA = "default look",
    /// iconB = "selected look". Slots 2-15 are evenly-spaced rainbow.
    static let palette: [UIImage] = (0..<16).map { i in
        let size: CGFloat = (i == 1) ? 60 : 44
        let hue = Double(i) / 16.0
        let fill: UIColor = (i == 0) ? UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1)
                          : (i == 1) ? UIColor(red: 0.99, green: 0.96, blue: 0.86, alpha: 1)
                          : UIColor(hue: hue, saturation: 0.35, brightness: 0.95, alpha: 1)
        let ring: UIColor = (i == 0) ? UIColor(red: 0.40, green: 0.30, blue: 0.16, alpha: 1)
                          : (i == 1) ? UIColor(red: 0.78, green: 0.32, blue: 0.20, alpha: 1)
                          : UIColor(hue: hue, saturation: 0.85, brightness: 0.45, alpha: 1)
        let dot:  UIColor = (i == 0) ? UIColor(red: 0.78, green: 0.32, blue: 0.20, alpha: 1)
                          : (i == 1) ? UIColor(red: 0.78, green: 0.32, blue: 0.20, alpha: 1)
                          : UIColor(hue: hue, saturation: 0.95, brightness: 0.65, alpha: 1)
        return pngBacked(render(size: size, fill: fill, ring: ring, dot: dot, ringWidth: i == 1 ? 2.2 : 1.6))
    }

    private static func render(size: CGFloat, fill: UIColor, ring: UIColor, dot: UIColor, ringWidth: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let c = ctx.cgContext
            let inset: CGFloat = max(4, size * 0.10)
            let disc = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
            c.setFillColor(fill.cgColor); c.fillEllipse(in: disc)
            c.setStrokeColor(ring.cgColor); c.setLineWidth(ringWidth)
            c.strokeEllipse(in: disc.insetBy(dx: ringWidth * 0.5, dy: ringWidth * 0.5))
            let dotInset = disc.width * 0.30
            c.setFillColor(dot.cgColor); c.fillEllipse(in: disc.insetBy(dx: dotInset, dy: dotInset))
        }
    }

    private static func pngBacked(_ image: UIImage) -> UIImage {
        guard let png = image.pngData(), let cg = UIImage(data: png)?.cgImage else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Same SHA256 that MapLibreSwiftDSL uses internally (Symbol.swift Symbol/Utilities).
    /// Empty string means cgImage?.dataProvider?.data was nil and the layer will
    /// collide with any other "empty-hash" image in the style registry.
    static func sha256(of image: UIImage) -> String {
        guard let cf = image.cgImage?.dataProvider?.data else { return "" }
        let data = cf as Data
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Grid coords

/// 4×4 grid of equator-area test points so the camera at zoom 4 sees all 16.
let gridCoords: [CLLocationCoordinate2D] = {
    var out: [CLLocationCoordinate2D] = []
    for row in 0..<4 {
        for col in 0..<4 {
            // Center around (0,0). Spacing ~6° between points.
            let lat = 9.0 - Double(row) * 6.0
            let lon = -9.0 + Double(col) * 6.0
            out.append(.init(latitude: lat, longitude: lon))
        }
    }
    return out
}()

// MARK: - Map

/// Use OpenFreeMap liberty as a remote basemap — no tile bundling needed for
/// the spike. If the device is offline, the markers still attempt to render
/// against the empty canvas, which is also informative.
private let styleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

struct ContentView: View {
    @State var camera: MapViewCamera = {
        if Scenario.current == .zoomedOneSelected {
            return .center(gridCoords[7], zoom: 9)
        }
        return .center(.init(latitude: 0, longitude: 0), zoom: 4)
    }()

    @State private var loadedStyle: MLNStyle?

    var body: some View {
        ZStack(alignment: .top) {
            MapView(styleURL: styleURL, camera: $camera) {
                scenarioLayers(Scenario.current)
            }
            .ignoresSafeArea()
            .onMapStyleLoaded { style in
                loadedStyle = style
                // For `raw-selected` scenario, add the selected feature DIRECTLY
                // via MLN APIs, completely bypassing the DSL.
                if Scenario.current == .rawSelected {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        Self.installRawSelected(in: style)
                    }
                }
                // Dump after DSL has had a chance to attach its layers.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    Self.dumpStyle(style)
                }
            }
            .onAppear { logHashes() }

            HStack {
                Text(Scenario.current.rawValue)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                Spacer()
            }.padding(.top, 56).padding(.horizontal, 12)
        }
    }

    @MapViewContentBuilder
    private func scenarioLayers(_ scenario: Scenario) -> [StyleLayerDefinition] {
        switch scenario {
        case .allDefault:
            singleSourceLayer(id: "all-default", image: SpikeIcons.palette[0], features: features(gridCoords))
        case .allSelected:
            singleSourceLayer(id: "all-selected", image: SpikeIcons.palette[1], features: features(gridCoords))
        case .oneSelected:
            // 15 default in one source, 1 selected (slot 7 — middle-ish) in another.
            let defaultCoords = gridCoords.enumerated().filter { $0.offset != 7 }.map { $0.element }
            singleSourceLayer(id: "one-default", image: SpikeIcons.palette[0], features: features(defaultCoords))
            singleSourceLayer(id: "one-selected", image: SpikeIcons.palette[1], features: features([gridCoords[7]]))
        case .allDifferent:
            for i in 0..<16 {
                singleSourceLayer(
                    id: "diff-\(i)",
                    image: SpikeIcons.palette[i],
                    features: features([gridCoords[i]])
                )
            }
        case .oneVivid:
            let defaultCoords = gridCoords.enumerated().filter { $0.offset != 7 }.map { $0.element }
            singleSourceLayer(id: "vivid-default", image: SpikeIcons.palette[0], features: features(defaultCoords))
            singleSourceLayer(id: "vivid-pick",    image: SpikeIcons.palette[10], features: features([gridCoords[7]]))
        case .selectedFirst:
            let defaultCoords = gridCoords.enumerated().filter { $0.offset != 7 }.map { $0.element }
            // Selected source FIRST in the builder
            singleSourceLayer(id: "sf-selected", image: SpikeIcons.palette[1], features: features([gridCoords[7]]))
            singleSourceLayer(id: "sf-default",  image: SpikeIcons.palette[0], features: features(defaultCoords))
        case .twoSingles:
            singleSourceLayer(id: "two-a", image: SpikeIcons.palette[0], features: features([gridCoords[5]]))
            singleSourceLayer(id: "two-b", image: SpikeIcons.palette[1], features: features([gridCoords[10]]))
        case .twoEqualSplit:
            let firstHalf  = Array(gridCoords.prefix(8))
            let secondHalf = Array(gridCoords.suffix(8))
            singleSourceLayer(id: "eq-a", image: SpikeIcons.palette[0], features: features(firstHalf))
            singleSourceLayer(id: "eq-b", image: SpikeIcons.palette[1], features: features(secondHalf))
        case .oneSelectedFlip:
            let bulkCoords = gridCoords.enumerated().filter { $0.offset != 7 }.map { $0.element }
            singleSourceLayer(id: "flip-bulk", image: SpikeIcons.palette[1], features: features(bulkCoords))
            singleSourceLayer(id: "flip-pick", image: SpikeIcons.palette[0], features: features([gridCoords[7]]))
        case .rawSelected:
            let defaultCoords = gridCoords.enumerated().filter { $0.offset != 7 }.map { $0.element }
            singleSourceLayer(id: "raw-default", image: SpikeIcons.palette[0], features: features(defaultCoords))
        case .zoomedOneSelected:
            let defaultCoords = gridCoords.enumerated().filter { $0.offset != 7 }.map { $0.element }
            singleSourceLayer(id: "z-default",  image: SpikeIcons.palette[0],  features: features(defaultCoords))
            singleSourceLayer(id: "z-selected", image: SpikeIcons.palette[10], features: features([gridCoords[7]]))
        }
    }

    private func singleSourceLayer(id: String, image: UIImage, features: [MLNPointFeature]) -> SymbolStyleLayer {
        let src = ShapeSource(identifier: "src-\(id)") { features }
        return SymbolStyleLayer(identifier: "lyr-\(id)", source: src)
            .iconImage(image)
            .iconAllowsOverlap(true)
            .iconAnchor("center")
    }

    private func features(_ coords: [CLLocationCoordinate2D]) -> [MLNPointFeature] {
        coords.enumerated().map { (i, c) in
            let f = MLNPointFeature()
            f.coordinate = c
            f.attributes = ["i": i]
            return f
        }
    }

    private func logHashes() {
        print("[SpikeIcons] scenario=\(Scenario.current.rawValue)")
        for (i, img) in SpikeIcons.palette.enumerated() {
            print("[SpikeIcons] palette[\(i)] sha256=\(SpikeIcons.sha256(of: img))")
        }
    }

    /// Add a "selected"-style point feature at slot 7 using raw MLN APIs only,
    /// no DSL involvement at all. If THIS renders when the DSL version does not,
    /// the bug is in the DSL.
    static func installRawSelected(in style: MLNStyle) {
        let img = SpikeIcons.palette[1]
        let imageName = "raw-selected-image"
        style.setImage(img, forName: imageName)

        let feature = MLNPointFeature()
        feature.coordinate = gridCoords[7]
        feature.attributes = ["i": 7]
        let source = MLNShapeSource(identifier: "raw-selected-src", features: [feature], options: nil)
        style.addSource(source)

        let layer = MLNSymbolStyleLayer(identifier: "raw-selected-lyr", source: source)
        layer.iconImageName = NSExpression(forConstantValue: imageName)
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconAnchor = NSExpression(forConstantValue: "center")
        style.addLayer(layer)
        print("[RawSelected] installed manually at \(gridCoords[7])")
    }

    /// Inspect MLNStyle to figure out exactly what the SwiftUI/DSL pipeline
    /// actually committed: which layers exist, which image names they reference,
    /// and which of those images are actually registered.
    static func dumpStyle(_ style: MLNStyle) {
        print("[StyleDump] === layers ===")
        for layer in style.layers {
            if let sym = layer as? MLNSymbolStyleLayer {
                let iconName = sym.iconImageName?.description ?? "nil"
                print("[StyleDump] symbol-layer id=\(sym.identifier) iconImageName=\(iconName)")
            } else {
                print("[StyleDump] other-layer  id=\(layer.identifier) class=\(type(of: layer))")
            }
        }
        print("[StyleDump] === sources ===")
        for source in style.sources {
            if let shape = source as? MLNShapeSource {
                let shapeDesc = shape.shape.map { "shape=\(type(of: $0))" } ?? "shape=nil"
                print("[StyleDump] shape-source id=\(shape.identifier) \(shapeDesc)")
                if let collection = shape.shape as? MLNShapeCollectionFeature {
                    print("[StyleDump]   collection.shapes.count=\(collection.shapes.count)")
                } else if let _ = shape.shape as? MLNPointFeature {
                    print("[StyleDump]   single-point feature")
                }
            } else {
                print("[StyleDump] other-source id=\(source.identifier) class=\(type(of: source))")
            }
        }
        print("[StyleDump] === image lookups for palette ===")
        for (i, img) in SpikeIcons.palette.enumerated() {
            let hash = SpikeIcons.sha256(of: img)
            let lookup = style.image(forName: hash)
            print("[StyleDump] palette[\(i)] hash=\(hash.prefix(12)) registered=\(lookup != nil) lookupSize=\(lookup?.size ?? .zero)")
        }
    }
}
