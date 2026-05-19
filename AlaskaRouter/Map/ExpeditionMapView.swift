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
    /// Map tap on a waypoint marker (AlaskaRouter-kcq8). `nil` means an empty
    /// area was tapped — the parent should clear selection.
    var onWaypointTap: ((UUID?) -> Void)? = nil

    /// Tappable layer ids for hit-test. Includes both default + selected
    /// marker layers so a stop can be selected regardless of current state.
    private static let waypointLayerIDs: Set<String> = [
        "trip-marker-default-icons",
        "trip-marker-selected-icons",
    ]

    var body: some View {
        MapView(styleURL: styleURL, camera: $camera) {
            if let trip {
                // Route geometry: snap-to-road from the Routing layer when
                // available, straight-line between waypoints as the offline /
                // pending-snap fallback (which is fine visually here — the
                // wash + core treatment looks like a highlighter either way).

                // Per-block translucent two-stroke pattern (design-handoff
                // mock, design/mocks/map.jsx). A wide soft "wash" plus a
                // tighter inner "core", both the block color, both round-
                // capped, no casing or outline — the road shows through.
                //
                // Widths scale with zoom; below z=8 we floor at a "good
                // pencil line" so the route stays readable when zoomed out.
                // *** Tweak these stops to adjust the route-line appearance. ***
                let washStops = NSExpression(forConstantValue: [
                    0.0:  8.0,    // floor: minimum wash width (z=0..8)
                    8.0:  8.0,
                    10.0: 14.0,
                    13.0: 26.0,
                    15.0: 44.0,
                    17.0: 72.0,
                ])
                let coreStops = NSExpression(forConstantValue: [
                    0.0:  4.0,    // floor: minimum core width (z=0..8)
                    8.0:  4.0,
                    10.0: 7.0,
                    13.0: 14.0,
                    15.0: 24.0,
                    17.0: 40.0,
                ])
                let widthCurve = NSExpression(forConstantValue: 1.5)

                let geoms = trip.blockGeometries(snappedCoords: snappedRouteCoords)
                // NB: `for entry in geoms` rather than `for (block, coords)` —
                // the MapViewContentBuilder + tuple destructuring combination
                // silently produces empty output.
                for entry in geoms {
                    let feature = MLNPolylineFeature(coordinates: entry.coords, count: UInt(entry.coords.count))
                    let src = ShapeSource(identifier: "trip-route-block-\(entry.block.id)") { feature }
                    let c = entry.block.color.swiftUIColor
                    let uic = UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0)

                    LineStyleLayer(identifier: "route-block-\(entry.block.id)-wash", source: src)
                        .lineColor(uic)
                        .lineCap(.round).lineJoin(.round).lineOpacity(0.18)
                        .lineWidth(interpolatedBy: .zoomLevel,
                                   curveType: .exponential,
                                   parameters: widthCurve,
                                   stops: washStops)
                    LineStyleLayer(identifier: "route-block-\(entry.block.id)", source: src)
                        .lineColor(uic)
                        .lineCap(.round).lineJoin(.round).lineOpacity(0.34)
                        .lineWidth(interpolatedBy: .zoomLevel,
                                   curveType: .exponential,
                                   parameters: widthCurve,
                                   stops: coreStops)
                }

                let ordered = trip.orderedWaypoints
                let selectedSet = ordered.filter { $0.id == selectedWaypointID }
                let unselectedSet = ordered.filter { $0.id != selectedWaypointID }

                // Default-style markers (everyone except the selected one).
                let unselectedFeatures = unselectedSet.map { wp -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = wp.coordinate
                    f.attributes = ["name": wp.label ?? "", "wpID": wp.id.uuidString]
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
                    f.attributes = ["name": wp.label ?? "", "wpID": wp.id.uuidString]
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
        // Map tap hit-tests against the two waypoint-marker layers. When a
        // marker is hit, fire onWaypointTap(UUID). Empty area → onWaypointTap(nil)
        // so the parent can dismiss selection / callout.
        .onTapMapGesture(on: Self.waypointLayerIDs) { _, features in
            guard let cb = onWaypointTap else { return }
            if let raw = features.first?.attribute(forKey: "wpID") as? String,
               let id = UUID(uuidString: raw) {
                cb(id)
            } else {
                cb(nil)
            }
        }
    }
}
