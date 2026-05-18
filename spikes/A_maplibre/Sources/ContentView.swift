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

/// Catmull-Rom spline through the waypoints — the v1 offline fallback. Same
/// algorithm we'll port into the real app's `SegmentGeometry.spline` rendering.
private func catmullRomSpline(_ waypoints: [CLLocationCoordinate2D], samplesPerSegment: Int = 40) -> [CLLocationCoordinate2D] {
    guard waypoints.count >= 2 else { return waypoints }
    // Pad with phantom endpoints (reflect first and last neighbors)
    let first = waypoints.first!, last = waypoints.last!
    let p0Phantom = CLLocationCoordinate2D(
        latitude: 2 * first.latitude - waypoints[1].latitude,
        longitude: 2 * first.longitude - waypoints[1].longitude
    )
    let pNPhantom = CLLocationCoordinate2D(
        latitude: 2 * last.latitude - waypoints[waypoints.count - 2].latitude,
        longitude: 2 * last.longitude - waypoints[waypoints.count - 2].longitude
    )
    let padded = [p0Phantom] + waypoints + [pNPhantom]
    var out: [CLLocationCoordinate2D] = []
    for i in 1..<padded.count - 2 {
        let p0 = padded[i - 1], p1 = padded[i], p2 = padded[i + 1], p3 = padded[i + 2]
        for s in 0..<samplesPerSegment {
            let t = Double(s) / Double(samplesPerSegment)
            let t2 = t * t, t3 = t2 * t
            let lat = 0.5 * (2 * p1.latitude
                + (-p0.latitude + p2.latitude) * t
                + (2 * p0.latitude - 5 * p1.latitude + 4 * p2.latitude - p3.latitude) * t2
                + (-p0.latitude + 3 * p1.latitude - 3 * p2.latitude + p3.latitude) * t3)
            let lon = 0.5 * (2 * p1.longitude
                + (-p0.longitude + p2.longitude) * t
                + (2 * p0.longitude - 5 * p1.longitude + 4 * p2.longitude - p3.longitude) * t2
                + (-p0.longitude + 3 * p1.longitude - 3 * p2.longitude + p3.longitude) * t3)
            out.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }
    out.append(last)
    return out
}

private enum RouteMode: String {
    case snapped, spline, straight
}

/// Route mode toggle — launch with `-routeMode spline|straight|snapped`.
private let routeMode: RouteMode = {
    let raw = UserDefaults.standard.string(forKey: "routeMode") ?? "snapped"
    return RouteMode(rawValue: raw) ?? .snapped
}()

/// Decode the bundled OSRM GeoJSON FeatureCollection → flat `[CLLocationCoordinate2D]`.
/// Parsing it ourselves (instead of via `MLNShape(data:encoding:)`) avoids a MapLibre C++
/// exception that gets thrown when a parsed `MLNShapeCollectionFeature` is passed to
/// `MLNShapeSource(features:)`.
private struct OSRMGeoJSON: Decodable {
    let features: [Feature]
    struct Feature: Decodable { let geometry: Geometry }
    struct Geometry: Decodable { let type: String; let coordinates: [[Double]] }
}

private func loadSnappedRouteCoords() -> [CLLocationCoordinate2D]? {
    guard let url = Bundle.main.url(forResource: "demo-route", withExtension: "geojson"),
          let data = try? Data(contentsOf: url),
          let fc = try? JSONDecoder().decode(OSRMGeoJSON.self, from: data),
          let geom = fc.features.first?.geometry,
          geom.type == "LineString" else { return nil }
    return geom.coordinates.compactMap {
        guard $0.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
    }
}

/// Resolved route geometry based on mode. Snapped = real OSRM road. Spline =
/// smooth Catmull-Rom curve (v1 offline-fallback look). Straight = simple polyline.
nonisolated(unsafe) private let demoRouteShape: MLNShape = {
    let coords = demoWaypoints.map(\.coord)
    switch routeMode {
    case .snapped:
        if let snapped = loadSnappedRouteCoords(), !snapped.isEmpty {
            print("[spike] route mode: snapped (OSRM, \(snapped.count) points)")
            return MLNPolylineFeature(coordinates: snapped, count: UInt(snapped.count))
        }
        print("[spike] snapped requested but demo-route.geojson missing; falling back to spline")
        fallthrough
    case .spline:
        let spline = catmullRomSpline(coords)
        print("[spike] route mode: spline (Catmull-Rom, \(spline.count) points)")
        return MLNPolylineFeature(coordinates: spline, count: UInt(spline.count))
    case .straight:
        print("[spike] route mode: straight (geodesic polyline, \(coords.count) waypoints)")
        return MLNPolylineFeature(coordinates: coords, count: UInt(coords.count))
    }
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
        // Bundled glyphs root: Bundle/glyphs/<fontstack>/<range>.pbf
        let glyphsBase = Bundle.main.bundleURL.appendingPathComponent("glyphs").absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "file://", with: "file:///") // ensure file:/// triple-slash
        // Patch two placeholders in this style.
        do {
            var json = try String(contentsOf: url, encoding: .utf8)
            json = json.replacingOccurrences(of: "__BASEMAP_URL__", with: pmtilesURL)
            json = json.replacingOccurrences(of: "__GLYPHS_URL_BASE__", with: glyphsBase)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("style-opentopomap-offline-resolved.json")
            try json.write(to: tmp, atomically: true, encoding: .utf8)
            print("[spike] patched offline style at \(tmp.path); glyphs base=\(glyphsBase)")
            return tmp
        } catch {
            fatalError("Failed to patch offline style: \(error)")
        }
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

// MARK: - Marker icon (programmatic cream disc + brown ring + colored center dot)

/// One reusable trip-waypoint marker. We use a single icon because MapLibreSwiftDSL's
/// per-feature `iconImage(featurePropertyNamed:mappings:default:)` is broken in our
/// package configuration (their own demo of it is commented out). For per-type icons
/// later we'll either fix the DSL or switch to per-kind ShapeSources.
private func makeWaypointIcon() -> UIImage {
    let size = CGSize(width: 44, height: 44)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        let c = ctx.cgContext
        // Drop shadow
        c.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3,
                    color: UIColor.black.withAlphaComponent(0.22).cgColor)
        // Outer disc — warm cream
        let outer = CGRect(x: 5, y: 5, width: 34, height: 34)
        c.setFillColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1.0).cgColor)
        c.fillEllipse(in: outer)
        // Reset shadow before stroking
        c.setShadow(offset: .zero, blur: 0, color: nil)
        // Brown ring
        c.setStrokeColor(UIColor(red: 0.40, green: 0.30, blue: 0.16, alpha: 0.95).cgColor)
        c.setLineWidth(1.6)
        c.strokeEllipse(in: outer.insetBy(dx: 0.8, dy: 0.8))
        // Center colored dot (trip color — warm tomato)
        let inner = outer.insetBy(dx: 9, dy: 9)
        c.setFillColor(UIColor(red: 0.78, green: 0.32, blue: 0.20, alpha: 1.0).cgColor)
        c.fillEllipse(in: inner)
    }
}

private let waypointIcon = makeWaypointIcon()

// MARK: - Camera

private let cameraStops: [(center: CLLocationCoordinate2D, zoom: Double, pitch: Double, bearing: Double)] = isOfflineDemo
    ? [
        // Frame the demo route, then zoom up on Fairbanks to answer the
        // "what does urban data look like on OpenTopoMap?" question.
        (.init(latitude: 64.0,  longitude: -148.5),   7.0, 0, 0),    // full route overview
        (.init(latitude: 63.95, longitude: -149.0),  10.0, 0, 0),    // Healy / route detail
        (.init(latitude: 64.838, longitude: -147.72), 11.0, 0, 0),   // Fairbanks wide
        (.init(latitude: 64.838, longitude: -147.72), 13.0, 0, 0),   // Fairbanks streets ⭐
        (.init(latitude: 64.838, longitude: -147.72), 14.0, 0, 0),   // Fairbanks buildings ⭐
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
                // --- Trip route polyline (snapped / spline / straight per launch arg) ---
                let routeSource = ShapeSource(identifier: "trip-route") { demoRouteShape }

                // Soft cream casing under the route for legibility on the topo basemap.
                LineStyleLayer(identifier: "route-casing", source: routeSource)
                    .lineColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 0.95))
                    .lineWidth(8.0)
                    .lineCap(.round).lineJoin(.round)

                // The route itself. Spline/straight modes are dashed to communicate
                // "pending precise routing" — this is the v1 pendingSnap visual hint.
                let routeLayer = LineStyleLayer(identifier: "route", source: routeSource)
                    .lineColor(UIColor(red: 0.78, green: 0.32, blue: 0.20, alpha: 1.0))
                    .lineWidth(4.0)
                    .lineCap(.round).lineJoin(.round)
                    .lineOpacity(0.92)
                switch routeMode {
                case .snapped: routeLayer
                case .spline:  routeLayer.lineDashPattern([3.0, 2.0])
                case .straight: routeLayer.lineDashPattern([1.5, 1.5])
                }

                // --- Waypoint markers ---
                let markerFeatures = demoWaypoints.map { wp -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = wp.coord
                    f.attributes = ["icon": wp.kind, "name": wp.name]
                    return f
                }
                let markersSource = ShapeSource(identifier: "trip-markers") { markerFeatures }

                SymbolStyleLayer(identifier: "trip-marker-icons", source: markersSource)
                    .iconImage(waypointIcon)
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
