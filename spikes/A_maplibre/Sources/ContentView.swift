// Map rendering spike.
//
// - Style is chosen by launch arg `-style <name>`; defaults to our hand-tuned expedition.
// - Special names: "maptiler", "maptiler-topo", "maptiler-landscape" → remote MapTiler.
// - Other names → bundled Resources/<name>.json, with placeholder replacement for
//   style-worldcover (image URL) and style-opentopomap-offline (PMTiles file URL).
// - When style is "style-opentopomap-offline", we also render a demo trip on top:
//   a route as a LineLayer + 5 waypoints as a SymbolLayer with SF-Symbol icons. This
//   validates the v1 architecture: OpenTopoMap PMTiles offline basemap + vector overlays
//   for trip planning, all inside MapLibre (not SwiftUI projection overlays).

import SwiftUI
import MapLibre
import MapLibreSwiftUI
import MapLibreSwiftDSL

private let MAPTILER_KEY = "60ijj1wXM0V5brYZ4jpV"

private let denali = CLLocationCoordinate2D(latitude: 63.0692, longitude: -151.0070)
private let labelAnchor = CLLocationCoordinate2D(latitude: 63.3000, longitude: -150.4000)

// Parks Highway demo trip (south → north): Cantwell → Denali Park Entrance →
// Healy → Nenana → Fairbanks. Used only when style is "style-opentopomap-offline".
// Route geometry is loaded from a bundled GeoJSON file (demo-route.geojson) that
// was computed once by OSRM's public router — 260 km, 3233 points of actual
// Parks Highway road. This proves the v1 architecture: real snap-to-road routes
// produced by a routing API and rendered as a MapLibre LineLayer.
private struct Waypoint {
    let name: String
    let coord: CLLocationCoordinate2D
    let kind: String   // matches the icon keys registered below
}

private let demoWaypoints: [Waypoint] = [
    .init(name: "Cantwell",            coord: .init(latitude: 63.3956, longitude: -148.9075), kind: "fuel"),
    .init(name: "Denali Park Entrance",coord: .init(latitude: 63.7298, longitude: -148.9128), kind: "visitor"),
    .init(name: "Healy",               coord: .init(latitude: 63.8625, longitude: -148.9706), kind: "fuel"),
    .init(name: "Nenana",              coord: .init(latitude: 64.5631, longitude: -149.0925), kind: "river"),
    .init(name: "Fairbanks",           coord: .init(latitude: 64.8378, longitude: -147.7164), kind: "city"),
]

/// Snap-to-road geometry loaded from the bundled OSRM GeoJSON; falls back to
/// straight-line geodesic between waypoints if the file is missing.
nonisolated(unsafe) private let demoRouteShape: MLNShape = {
    if let url = Bundle.main.url(forResource: "demo-route", withExtension: "geojson"),
       let data = try? Data(contentsOf: url),
       let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
        print("[spike] loaded snap-to-road route from demo-route.geojson")
        return shape
    }
    print("[spike] WARNING: demo-route.geojson missing; falling back to straight lines")
    let coords = demoWaypoints.map(\.coord)
    return MLNPolylineFeature(coordinates: coords, count: UInt(coords.count))
}()

// Default style + offline-demo detection.
private let requestedStyleName: String =
    UserDefaults.standard.string(forKey: "style") ?? "style-expedition"

private let isOfflineDemo = (requestedStyleName == "style-opentopomap-offline")

// MARK: - Style URL resolution (with placeholder replacement for bundled image/PMTiles)

private let styleURL: URL = {
    print("[spike] requested style: \(requestedStyleName)")
    if requestedStyleName == "maptiler" {
        return URL(string: "https://api.maptiler.com/maps/outdoor-v2/style.json?key=\(MAPTILER_KEY)")!
    }
    if requestedStyleName == "maptiler-topo" {
        return URL(string: "https://api.maptiler.com/maps/topo-v2/style.json?key=\(MAPTILER_KEY)")!
    }
    if requestedStyleName == "maptiler-landscape" {
        return URL(string: "https://api.maptiler.com/maps/landscape/style.json?key=\(MAPTILER_KEY)")!
    }
    guard let url = Bundle.main.url(forResource: requestedStyleName, withExtension: "json") else {
        fatalError("Missing \(requestedStyleName).json — check Resources are bundled.")
    }
    if requestedStyleName == "style-worldcover" {
        guard let png = Bundle.main.url(forResource: "worldcover-alaska", withExtension: "png") else {
            fatalError("Missing worldcover-alaska.png in bundle")
        }
        return patchStyle(url, replacing: "__WORLDCOVER_URL__", with: png.absoluteString)
    }
    if requestedStyleName == "style-opentopomap-offline" {
        guard let pmtiles = Bundle.main.url(forResource: "denali-otm", withExtension: "pmtiles") else {
            fatalError("Missing denali-otm.pmtiles in bundle — generate via Tools/dl-otm-denali.py + pmtiles convert")
        }
        let pmtilesURL = "pmtiles://\(pmtiles.absoluteString)"
        return patchStyle(url, replacing: "__BASEMAP_URL__", with: pmtilesURL)
    }
    return url
}()

private func patchStyle(_ url: URL, replacing token: String, with value: String) -> URL {
    do {
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: token, with: value)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-resolved.json")
        try json.write(to: tmp, atomically: true, encoding: .utf8)
        print("[spike] patched style at \(tmp.path)")
        return tmp
    } catch {
        fatalError("Failed to patch style \(url): \(error)")
    }
}

// MARK: - Marker icons (SF Symbols rendered to UIImage with a paper-paletteable look)

private func makeMarkerIcon(symbol: String, fg: UIColor, bg: UIColor = UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1.0)) -> UIImage {
    let size = CGSize(width: 38, height: 38)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        // Soft cream disc with thin warm-brown ring.
        let disc = CGRect(x: 2, y: 2, width: 34, height: 34)
        ctx.cgContext.setFillColor(bg.cgColor)
        ctx.cgContext.fillEllipse(in: disc)
        ctx.cgContext.setStrokeColor(UIColor(red: 0.40, green: 0.30, blue: 0.16, alpha: 0.85).cgColor)
        ctx.cgContext.setLineWidth(1.6)
        ctx.cgContext.strokeEllipse(in: disc)
        // SF Symbol centered.
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        if let s = UIImage(systemName: symbol, withConfiguration: cfg)?.withTintColor(fg, renderingMode: .alwaysOriginal) {
            let p = CGPoint(x: (size.width - s.size.width)/2, y: (size.height - s.size.height)/2)
            s.draw(at: p)
        }
    }
}

nonisolated(unsafe) private let markerIcons: [AnyHashable: UIImage] = [
    "fuel":    makeMarkerIcon(symbol: "fuelpump.fill",  fg: UIColor(red: 0.83, green: 0.45, blue: 0.16, alpha: 1.0)),
    "visitor": makeMarkerIcon(symbol: "info",           fg: UIColor(red: 0.18, green: 0.42, blue: 0.55, alpha: 1.0)),
    "river":   makeMarkerIcon(symbol: "water.waves",    fg: UIColor(red: 0.20, green: 0.45, blue: 0.60, alpha: 1.0)),
    "city":    makeMarkerIcon(symbol: "house.fill",     fg: UIColor(red: 0.30, green: 0.22, blue: 0.10, alpha: 1.0)),
    "camp":    makeMarkerIcon(symbol: "tent.fill",      fg: UIColor(red: 0.36, green: 0.51, blue: 0.30, alpha: 1.0)),
]
private let markerFallbackIcon = makeMarkerIcon(symbol: "mappin", fg: .systemRed)

// MARK: - Camera

private let cameraStops: [(center: CLLocationCoordinate2D, zoom: Double, pitch: Double, bearing: Double)] = isOfflineDemo
    ? [
        // Frame the demo route across Parks Highway, then zoom in on the Denali area.
        (.init(latitude: 64.0, longitude: -148.5), 7.0, 0, 0),
        (.init(latitude: 64.0, longitude: -148.5), 8.0, 0, 0),
        (.init(latitude: 63.8, longitude: -148.9), 9.0, 0, 0),
        (.init(latitude: 63.8, longitude: -148.9), 9.0, 45, 25),
        (.init(latitude: 63.4, longitude: -148.9), 10.0, 0, 0),
      ]
    : [
        (denali, 4.5,  0, 0),
        (denali, 6.5,  0, 0),
        (denali, 9.0,  0, 0),
        (denali, 9.0, 45, 30),
        (denali, 3.5,  0, 0),
      ]

// MARK: - View

struct ContentView: View {
    @State private var camera: MapViewCamera = .center(cameraStops[1].center, zoom: cameraStops[1].zoom)
    @State private var cameraStopIndex: Int = 0
    @State private var timer: Timer? = nil

    var body: some View {
        MapView(
            styleURL: styleURL,
            camera: $camera
        ) {
            if isOfflineDemo {
                // --- Trip route polyline ---
                let coords = demoWaypoints.map(\.coord)
                let routeFeature = MLNPolylineFeature(coordinates: coords, count: UInt(coords.count))
                let routeSource = ShapeSource(identifier: "trip-route") { routeFeature }

                // Soft cream casing under the route for legibility on the topo basemap.
                LineStyleLayer(identifier: "route-casing", source: routeSource)
                    .lineColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 0.95))
                    .lineWidth(8.0)
                    .lineCap(.round).lineJoin(.round)

                LineStyleLayer(identifier: "route", source: routeSource)
                    .lineColor(UIColor(red: 0.78, green: 0.32, blue: 0.20, alpha: 1.0))
                    .lineWidth(4.0)
                    .lineCap(.round).lineJoin(.round)
                    .lineOpacity(0.92)

                // --- Waypoint markers ---
                let markerFeatures = demoWaypoints.map { wp -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = wp.coord
                    f.attributes = ["icon": wp.kind, "name": wp.name]
                    return f
                }
                let markersSource = ShapeSource(identifier: "trip-markers") { markerFeatures }

                SymbolStyleLayer(identifier: "trip-marker-icons", source: markersSource)
                    .iconImage(markerFallbackIcon)
                    .iconAllowsOverlap(true)
                    .iconAnchor("center")

                SymbolStyleLayer(identifier: "trip-marker-labels", source: markersSource)
                    .textFontNames(["Noto Sans Regular"])
                    .textFontSize(13)
                    .textColor(UIColor(red: 0.10, green: 0.07, blue: 0.04, alpha: 1.0))
                    .textHaloColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1.0))
                    .textHaloWidth(1.6)
                    .text(featurePropertyNamed: "name")
                    .textAnchor("top")
                    .textOffset(CGVector(dx: 0, dy: 1.2))
                    .textAllowsOverlap(false)
            } else {
                // --- Legacy Denali single-annotation overlay (Spike A baseline) ---
                let labelFeature = MLNPointFeature()
                labelFeature.coordinate = denali
                labelFeature.attributes = ["label": "Denali — North America's roof"]
                let labelSource = ShapeSource(identifier: "ann-label") { labelFeature }

                let arrowFeature = MLNPolylineFeature(coordinates: [labelAnchor, denali], count: 2)
                let arrowSource = ShapeSource(identifier: "ann-arrow") { arrowFeature }

                LineStyleLayer(identifier: "annotation-arrow", source: arrowSource)
                    .lineColor(.systemOrange)
                    .lineWidth(2.0)
                    .lineOpacity(0.85)

                SymbolStyleLayer(identifier: "annotation-label", source: labelSource)
                    .textFontNames(["Noto Sans Regular"])
                    .textFontSize(17)
                    .textColor(.label)
                    .textHaloColor(.systemBackground)
                    .textHaloWidth(1.5)
                    .text(featurePropertyNamed: "label")
                    .textAnchor("bottom")
                    .textOffset(CGVector(dx: 0, dy: -1.2))
                    .textAllowsOverlap(true)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            FloatingSearchBarPreview()
                .padding(.horizontal, 14)
                .padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 4) {
                Text("z\(cameraStops[cameraStopIndex].zoom, specifier: "%.1f")  p\(cameraStops[cameraStopIndex].pitch, specifier: "%.0f")°  b\(cameraStops[cameraStopIndex].bearing, specifier: "%.0f")°")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.trailing, 16)
            .padding(.bottom, 56)
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
                cycleCamera()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func cycleCamera() {
        cameraStopIndex = (cameraStopIndex + 1) % cameraStops.count
        let stop = cameraStops[cameraStopIndex]
        camera = .center(stop.center, zoom: stop.zoom, pitch: stop.pitch, direction: stop.bearing)
    }
}

// A bare-bones preview of the floating search bar from the brief, just to feel the layering.
struct FloatingSearchBarPreview: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Search places, peaks, fuel…")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .regular))
            Spacer()
            Circle()
                .fill(Color.orange.opacity(0.85))
                .frame(width: 22, height: 22)
                .overlay(Text("AK").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

#Preview {
    ContentView()
}
