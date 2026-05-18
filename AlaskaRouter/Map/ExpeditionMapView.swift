// Map renderer for AlaskaRouter v1.
//
// Architecture (locked, see SPIKE_FINDINGS.md):
//   - Basemap: OpenTopoMap raster, bundled per-region as PMTiles, loaded offline.
//   - Glyphs: bundled Noto Sans PBFs for fully-offline label rendering.
//   - Overlay: trip route + waypoint markers as MapLibre vector layers.
//   - Snap-to-road: pre-computed by OSRM, stored as GeoJSON (v1 caches each segment).
//   - Offline fallback: Catmull-Rom spline (`SegmentGeometry.spline`), `pendingSnap = true`
//     until reconnection auto-refresh fires routing again.

import SwiftUI
import MapLibre
import MapLibreSwiftUI
import MapLibreSwiftDSL

// MARK: - Demo trip (placeholder until SwiftData lands)

private struct Waypoint {
    let name: String
    let coord: CLLocationCoordinate2D
}

private let demoWaypoints: [Waypoint] = [
    .init(name: "Cantwell",            coord: .init(latitude: 63.3956, longitude: -148.9075)),
    .init(name: "Denali Park Entrance",coord: .init(latitude: 63.7298, longitude: -148.9128)),
    .init(name: "Healy",               coord: .init(latitude: 63.8625, longitude: -148.9706)),
    .init(name: "Nenana",              coord: .init(latitude: 64.5631, longitude: -149.0925)),
    .init(name: "Fairbanks",           coord: .init(latitude: 64.8378, longitude: -147.7164)),
]

// MARK: - Style resolution (patches bundle URLs into the style template)

private let styleURL: URL = {
    guard let templateURL = Bundle.main.url(forResource: "style-base", withExtension: "json") else {
        fatalError("Missing style-base.json in bundle")
    }
    guard let pmtilesURL = Bundle.main.url(forResource: "denali-otm", withExtension: "pmtiles") else {
        fatalError("Missing denali-otm.pmtiles in bundle")
    }
    let pmtilesRef = "pmtiles://\(pmtilesURL.absoluteString)"
    let glyphsBase = Bundle.main.bundleURL.appendingPathComponent("glyphs").absoluteString
        .replacingOccurrences(of: "file://", with: "file:///")
    do {
        var json = try String(contentsOf: templateURL, encoding: .utf8)
        json = json.replacingOccurrences(of: "__BASEMAP_URL__", with: pmtilesRef)
        json = json.replacingOccurrences(of: "__GLYPHS_URL_BASE__", with: glyphsBase)
        let resolved = FileManager.default.temporaryDirectory
            .appendingPathComponent("style-base-resolved.json")
        try json.write(to: resolved, atomically: true, encoding: .utf8)
        return resolved
    } catch {
        fatalError("Failed to resolve style URL placeholders: \(error)")
    }
}()

// MARK: - GeoJSON loader for the OSRM-snapped demo route

private struct OSRMGeoJSON: Decodable {
    let features: [Feature]
    struct Feature: Decodable { let geometry: Geometry }
    struct Geometry: Decodable { let type: String; let coordinates: [[Double]] }
}

private func loadSnappedRouteCoords() -> [CLLocationCoordinate2D] {
    guard let url = Bundle.main.url(forResource: "demo-route", withExtension: "geojson"),
          let data = try? Data(contentsOf: url),
          let fc = try? JSONDecoder().decode(OSRMGeoJSON.self, from: data),
          let geom = fc.features.first?.geometry,
          geom.type == "LineString" else { return [] }
    return geom.coordinates.compactMap {
        guard $0.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
    }
}

// MARK: - Marker icon (cream disc + brown ring + warm-tomato dot, programmatic)

private func makeWaypointIcon() -> UIImage {
    let size = CGSize(width: 44, height: 44)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        let c = ctx.cgContext
        c.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3,
                    color: UIColor.black.withAlphaComponent(0.22).cgColor)
        let outer = CGRect(x: 5, y: 5, width: 34, height: 34)
        c.setFillColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1.0).cgColor)
        c.fillEllipse(in: outer)
        c.setShadow(offset: .zero, blur: 0, color: nil)
        c.setStrokeColor(UIColor(red: 0.40, green: 0.30, blue: 0.16, alpha: 0.95).cgColor)
        c.setLineWidth(1.6)
        c.strokeEllipse(in: outer.insetBy(dx: 0.8, dy: 0.8))
        c.setFillColor(UIColor(red: 0.78, green: 0.32, blue: 0.20, alpha: 1.0).cgColor)
        c.fillEllipse(in: outer.insetBy(dx: 9, dy: 9))
    }
}

private let waypointIcon = makeWaypointIcon()

// MARK: - The view

struct ExpeditionMapView: View {
    // Center on Healy (mid-route) at a planning zoom; lets the bundled Denali pack show off.
    @State private var camera: MapViewCamera = .center(
        .init(latitude: 63.95, longitude: -148.9), zoom: 8.5
    )

    var body: some View {
        MapView(styleURL: styleURL, camera: $camera) {
            let routeCoords = loadSnappedRouteCoords()
            let routeFeature = MLNPolylineFeature(coordinates: routeCoords,
                                                  count: UInt(routeCoords.count))
            let routeSource = ShapeSource(identifier: "trip-route") { routeFeature }

            LineStyleLayer(identifier: "route-casing", source: routeSource)
                .lineColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 0.95))
                .lineWidth(8.0).lineCap(.round).lineJoin(.round)

            LineStyleLayer(identifier: "route", source: routeSource)
                .lineColor(UIColor(red: 0.78, green: 0.32, blue: 0.20, alpha: 1.0))
                .lineWidth(4.0).lineCap(.round).lineJoin(.round).lineOpacity(0.92)

            let markerFeatures = demoWaypoints.map { wp -> MLNPointFeature in
                let f = MLNPointFeature()
                f.coordinate = wp.coord
                f.attributes = ["name": wp.name]
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
        }
    }
}
