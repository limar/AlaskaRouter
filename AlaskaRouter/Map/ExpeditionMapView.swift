// Map renderer for AlaskaRouter v1.
//
// Architecture (locked, see SPIKE_FINDINGS.md):
//   - Basemap: OpenTopoMap raster, bundled per-region as PMTiles, loaded offline.
//   - Glyphs: bundled Noto Sans PBFs for fully-offline label rendering.
//   - Overlay: trip route + waypoint markers as MapLibre vector layers.
//   - v1: route geometry comes from a bundled OSRM-snapped GeoJSON associated
//     with the seeded sample trip. When routing layer lands, this will be
//     replaced with per-RouteSegment cached geometry from SwiftData.

import SwiftUI
import MapLibre
import MapLibreSwiftUI
import MapLibreSwiftDSL

// MARK: - Style resolution (patches bundle URLs into the style template)

private let styleURL: URL = {
    guard let templateURL = Bundle.main.url(forResource: "style-base", withExtension: "json") else {
        fatalError("Missing style-base.json in bundle")
    }
    guard let pmtilesURL = Bundle.main.url(forResource: "alaska-pack", withExtension: "pmtiles") else {
        fatalError("Missing alaska-pack.pmtiles in bundle")
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

// Default route geometry: straight-line polyline between consecutive waypoints.
// Used when no snap-to-road result is available (offline, awaiting routing, etc).
// Rendered dashed in this case to signal "pendingSnap".
private func straightRouteCoords(for trip: Trip) -> [CLLocationCoordinate2D] {
    trip.orderedWaypoints.map(\.coordinate)
}

// MARK: - The view

struct ExpeditionMapView: View {
    @Binding var camera: MapViewCamera
    let trip: Trip?
    let selectedWaypointID: UUID?
    let previewCoord: CLLocationCoordinate2D?
    let previewName: String?
    /// Snap-to-road geometry from the Routing layer. When present, replaces
    /// the straight-line fallback with the real road shape (solid, not dashed).
    let snappedRouteCoords: [CLLocationCoordinate2D]?

    var body: some View {
        MapView(styleURL: styleURL, camera: $camera) {
            if let trip {
                // Prefer the snapped geometry if it's available and matches the trip.
                let isSnapped = (snappedRouteCoords != nil)
                let coords = snappedRouteCoords ?? straightRouteCoords(for: trip)
                if coords.count >= 2 {
                    let routeFeature = MLNPolylineFeature(coordinates: coords, count: UInt(coords.count))
                    let routeSource = ShapeSource(identifier: "trip-route") { routeFeature }

                    LineStyleLayer(identifier: "route-casing", source: routeSource)
                        .lineColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 0.95))
                        .lineWidth(8.0).lineCap(.round).lineJoin(.round)

                    let c = trip.color.swiftUIColor
                    // Solid when snap-to-road geometry is in hand; dashed (pendingSnap) otherwise.
                    let routeLayer = LineStyleLayer(identifier: "route", source: routeSource)
                        .lineColor(UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0))
                        .lineWidth(4.0).lineCap(.round).lineJoin(.round).lineOpacity(0.92)
                    if isSnapped {
                        routeLayer
                    } else {
                        routeLayer.lineDashPattern([3.0, 2.0])
                    }
                }

                let ordered = trip.orderedWaypoints
                let selectedSet = ordered.filter { $0.id == selectedWaypointID }
                let unselectedSet = ordered.filter { $0.id != selectedWaypointID }

                // Default-style markers (everyone except the selected one).
                let unselectedFeatures = unselectedSet.map { wp -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = wp.coordinate
                    f.attributes = ["name": wp.label ?? ""]
                    return f
                }
                if !unselectedFeatures.isEmpty {
                    let src = ShapeSource(identifier: "trip-markers-default") { unselectedFeatures }
                    SymbolStyleLayer(identifier: "trip-marker-default-icons", source: src)
                        .iconImage(WaypointIcons.committedDefault)
                        .iconAllowsOverlap(true)
                        .iconAnchor("center")
                    SymbolStyleLayer(identifier: "trip-marker-default-labels", source: src)
                        .textFontNames(["Noto Sans Regular"])
                        .textFontSize(13)
                        .textColor(UIColor(red: 0.10, green: 0.07, blue: 0.04, alpha: 1.0))
                        .textHaloColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1.0))
                        .textHaloWidth(1.6)
                        .text(featurePropertyNamed: "name")
                        .textAnchor("top")
                        .textOffset(CGVector(dx: 0, dy: 1.4))
                        .textAllowsOverlap(false)
                }

                // Selected (sobresaliente) marker — rendered on top, bigger.
                let selectedFeatures = selectedSet.map { wp -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = wp.coordinate
                    f.attributes = ["name": wp.label ?? ""]
                    return f
                }
                if !selectedFeatures.isEmpty {
                    let src = ShapeSource(identifier: "trip-markers-selected") { selectedFeatures }
                    SymbolStyleLayer(identifier: "trip-marker-selected-icons", source: src)
                        .iconImage(WaypointIcons.committedSelected)
                        .iconAllowsOverlap(true)
                        .iconAnchor("center")
                    SymbolStyleLayer(identifier: "trip-marker-selected-labels", source: src)
                        // We only bundle Noto Sans Regular glyphs (see AlaskaRouter/glyphs/).
                        // Requesting "Noto Sans Bold" makes MapLibre fail the entire symbol —
                        // BOTH icon and label disappear. Use the bundled font; distinction
                        // comes from size + halo + the bigger selected icon.
                        .textFontNames(["Noto Sans Regular"])
                        .textFontSize(14)
                        .textColor(UIColor(red: 0.10, green: 0.07, blue: 0.04, alpha: 1.0))
                        .textHaloColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1.0))
                        .textHaloWidth(1.8)
                        .text(featurePropertyNamed: "name")
                        .textAnchor("top")
                        .textOffset(CGVector(dx: 0, dy: 1.8))
                        .textAllowsOverlap(false)
                }
            }

            // Preview pin (investigating a search result, not yet added).
            if let pc = previewCoord {
                let pf = MLNPointFeature()
                pf.coordinate = pc
                pf.attributes = ["name": previewName ?? ""]
                let src = ShapeSource(identifier: "preview-pin") { pf }
                SymbolStyleLayer(identifier: "preview-pin-icon", source: src)
                    .iconImage(WaypointIcons.preview)
                    .iconAllowsOverlap(true)
                    .iconAnchor("center")
            }
        }
    }
}
