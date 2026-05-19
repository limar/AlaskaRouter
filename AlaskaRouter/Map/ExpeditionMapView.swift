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

/// AlaskaRouter-02pm — palette variants. v0 returns the production
/// TripColor RGB tuple. v1 returns a punchier saturated version.
/// v2/v3 reuse v0 (their differentiation is in width/casing/outline).
private func variantColor(for color: TripColor, variant: Int) -> TripColor.ColorTuple {
    if variant == 1 || variant == 4 || variant == 5 || variant == 6 {
        switch color {
        case .amber:      return .init(red: 0.88, green: 0.20, blue: 0.10)   // crimson
        case .teal:       return .init(red: 0.08, green: 0.42, blue: 0.78)   // cobalt
        case .terracotta: return .init(red: 0.92, green: 0.50, blue: 0.10)   // burnt orange
        case .sage:       return .init(red: 0.18, green: 0.55, blue: 0.20)   // forest green
        case .indigo:     return .init(red: 0.42, green: 0.20, blue: 0.68)   // deep violet
        case .slate:      return .init(red: 0.28, green: 0.28, blue: 0.32)   // dark gray
        }
    }
    // v11: exact palette from the design-handoff mock (design/mocks/map.jsx).
    if variant == 11 {
        switch color {
        case .amber:      return .init(red: 0.760, green: 0.255, blue: 0.047) // #c2410c burnt orange
        case .teal:       return .init(red: 0.114, green: 0.306, blue: 0.847) // #1d4ed8 royal blue
        case .terracotta: return .init(red: 0.882, green: 0.114, blue: 0.282) // #e11d48 rose
        case .sage:       return .init(red: 0.082, green: 0.502, blue: 0.239) // #15803d forest green
        case .indigo:     return .init(red: 0.427, green: 0.157, blue: 0.851) // #6d28d9 violet
        case .slate:      return .init(red: 0.216, green: 0.255, blue: 0.318) // #374151 charcoal
        }
    }
    return color.swiftUIColor
}

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
                let wholeCoords = snappedRouteCoords ?? straightRouteCoords(for: trip)

                // AlaskaRouter-02pm — temporary variant switch. v0 is the
                // current production look. v1..v5 are experiments.
                let variant = LaunchArgs.routePaletteVariant
                let drawCasing = !(variant == 4 || variant == 5 || variant == 6
                                   || variant == 7 || variant == 8
                                   || variant == 9 || variant == 10
                                   || variant == 11)
                let casingWidth: Float = (variant == 2) ? 7.0 : 8.0
                let casingOpacity: Float = (variant == 2) ? 0.75 : 0.95
                let blockLineWidth: Float = {
                    switch variant {
                    case 1: return 5.0
                    case 2: return 6.0
                    case 3: return 4.0
                    case 4: return 6.0
                    case 5: return 5.0
                    case 6: return 7.0
                    case 7: return 5.0          // highlighter
                    case 8: return 5.0          // colored pencil (dashed grain)
                    case 9: return 14.0         // fat highlighter
                    case 10: return 18.0        // very fat highlighter
                    default: return 4.0
                    }
                }()
                let darkOutlineExtra: Float = {
                    switch variant {
                    case 3, 4: return 2.5
                    case 6:    return 1.0       // hairline outline
                    default:   return 0.0
                    }
                }()
                let blockOpacity: Float = {
                    switch variant {
                    case 7: return 0.55         // highlighter — see-through
                    case 8: return 0.78         // pencil — slightly less transparent
                    case 9: return 0.45         // fat highlighter
                    case 10: return 0.40        // very fat highlighter
                    default: return 1.0
                    }
                }()
                // Fine dash so the line reads as "grainy pencil" rather than
                // a solid brushstroke. Only used for variant 8.
                let pencilDashPattern: [Float]? = (variant == 8) ? [2.5, 0.7] : nil

                // Single shared casing under the entire route (cream halo).
                if drawCasing && wholeCoords.count >= 2 {
                    let casingFeature = MLNPolylineFeature(coordinates: wholeCoords, count: UInt(wholeCoords.count))
                    let casingSource = ShapeSource(identifier: "trip-route-casing") { casingFeature }
                    LineStyleLayer(identifier: "route-casing", source: casingSource)
                        .lineColor(UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 0.95))
                        .lineWidth(casingWidth).lineCap(.round).lineJoin(.round).lineOpacity(casingOpacity)
                }

                // One line layer per block, each in its block color. For
                // single-block trips this yields exactly one layer in the
                // trip's primary color (same as before this change).
                // NB: `for entry in geoms` rather than `for (block, coords)` —
                // the MapViewContentBuilder + tuple destructuring combination
                // silently produced empty output in earlier tests.
                let geoms = trip.blockGeometries(snappedCoords: snappedRouteCoords)
                for entry in geoms {
                    let feature = MLNPolylineFeature(coordinates: entry.coords, count: UInt(entry.coords.count))
                    let src = ShapeSource(identifier: "trip-route-block-\(entry.block.id)") { feature }
                    let c = variantColor(for: entry.block.color, variant: variant)
                    let uic = UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0)

                    // v11: design-handoff mock — two stacked translucent strokes
                    // (wide wash + tighter inner core). Widths scale with zoom
                    // so the highlight stays meaningfully wider than the road
                    // at every level. Stops are roughly tuned so the highlight
                    // sits at ~3× road width across z=6..17.
                    if variant == 11 {
                        let washStops = NSExpression(forConstantValue: [
                            6.0:  3.0,
                            10.0: 12.0,
                            13.0: 24.0,
                            15.0: 44.0,
                            17.0: 72.0,
                        ])
                        let coreStops = NSExpression(forConstantValue: [
                            6.0:  1.5,
                            10.0: 6.0,
                            13.0: 13.0,
                            15.0: 24.0,
                            17.0: 40.0,
                        ])
                        LineStyleLayer(identifier: "route-block-\(entry.block.id)-wash", source: src)
                            .lineColor(uic)
                            .lineCap(.round).lineJoin(.round).lineOpacity(0.18)
                            .lineWidth(interpolatedBy: .zoomLevel,
                                       curveType: .exponential,
                                       parameters: NSExpression(forConstantValue: 1.5),
                                       stops: washStops)
                        LineStyleLayer(identifier: "route-block-\(entry.block.id)", source: src)
                            .lineColor(uic)
                            .lineCap(.round).lineJoin(.round).lineOpacity(0.34)
                            .lineWidth(interpolatedBy: .zoomLevel,
                                       curveType: .exponential,
                                       parameters: NSExpression(forConstantValue: 1.5),
                                       stops: coreStops)
                    } else {
                        // Variants 3 & 4: dark outline UNDER the colored line.
                        if darkOutlineExtra > 0 {
                            LineStyleLayer(identifier: "route-block-\(entry.block.id)-outline", source: src)
                                .lineColor(UIColor(red: 0.20, green: 0.12, blue: 0.06, alpha: 0.85))
                                .lineWidth(blockLineWidth + darkOutlineExtra)
                                .lineCap(.round).lineJoin(.round)
                        }

                        let layer = LineStyleLayer(identifier: "route-block-\(entry.block.id)", source: src)
                            .lineColor(uic)
                            .lineWidth(blockLineWidth).lineCap(.round).lineJoin(.round).lineOpacity(blockOpacity)
                        if let pencilDash = pencilDashPattern {
                            layer.lineDashPattern(pencilDash)
                        } else if isSnapped {
                            layer
                        } else {
                            layer.lineDashPattern([3.0, 2.0])
                        }
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
