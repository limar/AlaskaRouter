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
    guard let anchorLabelsURL = Bundle.main.url(forResource: "alaska-anchor-labels", withExtension: "geojson") else {
        fatalError("Missing alaska-anchor-labels.geojson in bundle")
    }
    let pmtilesRef = "pmtiles://\(pmtilesURL.absoluteString)"
    let glyphsBase = Bundle.main.bundleURL.appendingPathComponent("glyphs").absoluteString
        .replacingOccurrences(of: "file://", with: "file:///")
    do {
        var json = try String(contentsOf: templateURL, encoding: .utf8)
        json = json.replacingOccurrences(of: "__BASEMAP_URL__", with: pmtilesRef)
        json = json.replacingOccurrences(of: "__GLYPHS_URL_BASE__", with: glyphsBase)
        json = json.replacingOccurrences(of: "__ANCHOR_LABELS_URL__", with: anchorLabelsURL.absoluteString)
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
    /// User's current GPS location (AlaskaRouter-j03u). When present, a blue
    /// puck is drawn at this coord. Pixel-sized so it stays constant across
    /// zooms (uses the WaypointIcons.userLocation UIImage).
    let userLocation: CLLocationCoordinate2D?
    /// Map tap on a waypoint marker (AlaskaRouter-kcq8). `nil` means an empty
    /// area was tapped — the parent should clear selection.
    var onWaypointTap: ((UUID?) -> Void)? = nil

    /// Tappable layer ids for hit-test. Includes both default + selected
    /// marker layers so a stop can be selected regardless of current state.
    private static let waypointLayerIDs: Set<String> = [
        "trip-marker-default-icons",
        "trip-marker-selected-icons",
    ]

    // MARK: - Ring A spike (AlaskaRouter-39eu, throwaway)

    /// Installs the Ring A probe layers for native `lineOffset`. Gated by
    /// the `-spikeRingA` launch arg. Idempotent — checks for existing source
    /// IDs because `unsafeMapViewControllerModifier` re-runs on every
    /// `updateUIView`.
    ///
    /// Two test polylines:
    /// 1. **Straight** — 3 points S→N at lon=-149.0. Baseline (red, offset 0)
    ///    + offset (blue, +30pt). Already confirmed A1.a/b/c.
    /// 2. **Curvy** — the bundled demo-route OSRM snap (Parks Highway,
    ///    ~3000 points, real curves around Healy). Baseline (orange, offset 0)
    ///    + offset (purple, +20pt). Answers A1.d: does the renderer handle
    ///    curves without self-intersection?
    fileprivate static func installRingASpike(into style: MLNStyle) {
        // CLEAN, FOCUSED TEST:
        //   Dark-orange — the demo route (bundled OSRM snap of Parks Highway).
        //     This is the ROAD. Where we want the offset line to be parallel to.
        //   Purple — same polyline, with native lineOffset = 7pt.
        //     Where MapLibre's renderer puts the offset.
        //
        // What "passing" looks like: purple is a thin clean ribbon ~7pt to
        // the right of the dark-orange road line, hugging every bend.
        // What "failing" looks like: knots, loops, bowing wider than 7pt at
        // tight bends. We saw both at z=10 last round.
        guard let url = Bundle.main.url(forResource: "demo-route", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]],
              let geom = features.first?["geometry"] as? [String: Any],
              let raw = geom["coordinates"] as? [[Double]] else {
            print("[spike-A] could not load demo-route.geojson")
            return
        }
        let coords: [CLLocationCoordinate2D] = raw.compactMap {
            guard $0.count >= 2 else { return nil }
            return .init(latitude: $0[1], longitude: $0[0])
        }

        // Reference — thin black line showing where the road centerline IS.
        ExpeditionMapView.addRoadReferenceLine(
            style: style,
            coords: coords,
            id: "spike-A-road-ref"
        )

        // 4-pass onion (W = 10pt, lanes at ±0.5W and ±1.5W).
        // Outer→inner: dark-orange (forward 2nd), orange (forward 1st),
        // purple (backward 1st), dark-purple (backward 2nd).
        // ADDED IN ORDER: outer lanes first so inner overlaps them where
        // bend geometry produces overlap.
        ExpeditionMapView.addSpikeLayer(
            style: style,
            coords: coords,
            id: "spike-A-forward-2",
            color: UIColor(red: 0.78, green: 0.38, blue: 0.10, alpha: 1.0), // dark orange
            offset: -15
        )
        ExpeditionMapView.addSpikeLayer(
            style: style,
            coords: coords,
            id: "spike-A-backward-2",
            color: UIColor(red: 0.34, green: 0.10, blue: 0.50, alpha: 1.0), // dark purple
            offset: 15
        )
        ExpeditionMapView.addSpikeLayer(
            style: style,
            coords: coords,
            id: "spike-A-forward-1",
            color: .systemOrange,
            offset: -5
        )
        ExpeditionMapView.addSpikeLayer(
            style: style,
            coords: coords,
            id: "spike-A-backward-1",
            color: .systemPurple,
            offset: 5
        )
    }

    /// Helper: add a thin black reference line showing the actual road
    /// centerline. Used in the Ring A spike so we can visually verify the
    /// two offset highlights sit symmetrically about the road.
    fileprivate static func addRoadReferenceLine(
        style: MLNStyle,
        coords: [CLLocationCoordinate2D],
        id: String
    ) {
        guard coords.count >= 2 else { return }
        let srcID = id + "-src"
        if style.source(withIdentifier: srcID) != nil { return }
        let polyline = MLNPolylineFeature(coordinates: coords, count: UInt(coords.count))
        let source = MLNShapeSource(identifier: srcID, shape: polyline, options: nil)
        style.addSource(source)
        let layer = MLNLineStyleLayer(identifier: id, source: source)
        layer.lineColor = NSExpression(forConstantValue: UIColor.black)
        layer.lineWidth = NSExpression(forConstantValue: 1)
        layer.lineOpacity = NSExpression(forConstantValue: 0.85)
        style.addLayer(layer)
    }

    /// Helper: add a polyline + a single core line layer to the style.
    /// No wash — testing the "highlighter pen" / "pencil" style where the
    /// stroke is a solid mark and the only color zones in a multi-pass
    /// scene are { lane1, lane2, overlap }.
    fileprivate static func addSpikeLayer(
        style: MLNStyle,
        coords: [CLLocationCoordinate2D],
        id: String,
        color: UIColor,
        offset: Double
    ) {
        guard coords.count >= 2 else { return }
        let srcID = id + "-src"
        if style.source(withIdentifier: srcID) != nil { return }
        let polyline = MLNPolylineFeature(coordinates: coords, count: UInt(coords.count))
        let source = MLNShapeSource(identifier: srcID, shape: polyline, options: nil)
        style.addSource(source)

        // Core only — wider than production core (7pt → 10pt) to give the
        // "highlighter mark" presence without a wash backing it.
        let core = MLNLineStyleLayer(identifier: id + "-core", source: source)
        core.lineColor = NSExpression(forConstantValue: color)
        core.lineWidth = NSExpression(forConstantValue: 10)
        core.lineOpacity = NSExpression(forConstantValue: 0.55)
        core.lineCap = NSExpression(forConstantValue: "round")
        core.lineJoin = NSExpression(forConstantValue: "round")
        if offset != 0 {
            core.lineOffset = NSExpression(forConstantValue: offset)
        }
        style.addLayer(core)
    }

    /// Branch γ candidate — windowed-tangent offset. For each output vertex,
    /// the tangent is computed from a WIDE window of neighbors (not the
    /// immediate prev/next as in our broken 3bot attempts) before computing
    /// the perpendicular. The wider window low-pass-filters the tangent
    /// direction, so it doesn't flip on micro-bends where the local turn
    /// radius < offset distance.
    ///
    /// Approximate Mercator-aware (cos(latitude) lon correction). Does NOT
    /// detect or repair self-intersection — relies on the windowed tangent
    /// to be smooth enough that self-intersection doesn't arise in the
    /// first place. If it does, we'll see it visually and step up to a
    /// proper offset-curve algorithm.
    fileprivate static func windowedTangentOffset(
        _ coords: [CLLocationCoordinate2D],
        offsetPoints: Double,
        window: Int
    ) -> [CLLocationCoordinate2D] {
        guard coords.count >= 2 else { return coords }
        // 1° lat ≈ 728 screen px at z=10 (256 × 2^10 / 360). So 1 pt offset
        // ≈ 1/728 ° lat. Matches the algebra in TripSegments.swift.
        let offsetDeg = offsetPoints / 728.0
        let half = max(1, window / 2)
        return (0 ..< coords.count).map { i in
            let prevIdx = max(0, i - half)
            let nextIdx = min(coords.count - 1, i + half)
            let prev = coords[prevIdx]
            let next = coords[nextIdx]
            let cosLat = max(cos(coords[i].latitude * .pi / 180.0), 0.1)
            let dLat = next.latitude - prev.latitude
            let dLonScreen = (next.longitude - prev.longitude) * cosLat
            let len = (dLat * dLat + dLonScreen * dLonScreen).squareRoot()
            guard len > 1e-12 else { return coords[i] }
            let perpLatScreen = -dLonScreen / len * offsetDeg
            let perpLonScreen =  dLat / len * offsetDeg
            return .init(
                latitude: coords[i].latitude + perpLatScreen,
                longitude: coords[i].longitude + perpLonScreen / cosLat
            )
        }
    }

    /// Helper: moving-average smoothing for a polyline. Each output point is
    /// the average of the `window` nearest input points (clamped at the
    /// edges). Used to attenuate micro-jitter in the OSRM snap so the
    /// per-vertex perpendicular doesn't flip.
    fileprivate static func movingAverage(
        _ coords: [CLLocationCoordinate2D],
        window: Int
    ) -> [CLLocationCoordinate2D] {
        guard window >= 2, coords.count >= window else { return coords }
        let half = window / 2
        return (0 ..< coords.count).map { i in
            let lo = max(0, i - half)
            let hi = min(coords.count - 1, i + half)
            let slice = coords[lo...hi]
            let n = Double(slice.count)
            let lat = slice.reduce(0.0) { $0 + $1.latitude } / n
            let lon = slice.reduce(0.0) { $0 + $1.longitude } / n
            return .init(latitude: lat, longitude: lon)
        }
    }

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

                // Iterate SEGMENTS (one leg per consecutive waypoint pair)
                // instead of whole blocks. Each segment carries a perpendicular
                // pass-offset and may be flagged as an "extra pass" (dashed) —
                // see Trip.passOffsetSegments + AlaskaRouter-9axu.
                let segments = trip.passOffsetSegments(snappedCoords: snappedRouteCoords)
                for seg in segments {
                    let feature = MLNPolylineFeature(coordinates: seg.coords, count: UInt(seg.coords.count))
                    let src = ShapeSource(identifier: "trip-route-seg-\(seg.id)") { feature }
                    let c = seg.color.swiftUIColor
                    let uic = UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0)

                    let washLayer = LineStyleLayer(identifier: "route-seg-\(seg.id)-wash", source: src)
                        .lineColor(uic)
                        .lineCap(.round).lineJoin(.round).lineOpacity(0.18)
                        .lineWidth(interpolatedBy: .zoomLevel,
                                   curveType: .exponential,
                                   parameters: widthCurve,
                                   stops: washStops)
                    let coreLayer = LineStyleLayer(identifier: "route-seg-\(seg.id)", source: src)
                        .lineColor(uic)
                        .lineCap(.round).lineJoin(.round).lineOpacity(0.34)
                        .lineWidth(interpolatedBy: .zoomLevel,
                                   curveType: .exponential,
                                   parameters: widthCurve,
                                   stops: coreStops)
                    if seg.isExtraPass {
                        washLayer.lineDashPattern([2.0, 1.5])
                        coreLayer.lineDashPattern([2.0, 1.5])
                    } else {
                        washLayer
                        coreLayer
                    }
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

            // User's current GPS location — Apple-Maps-style blue puck.
            if let userLocation {
                let f = MLNPointFeature()
                f.coordinate = userLocation
                let src = ShapeSource(identifier: "user-location") { f }
                SymbolStyleLayer(identifier: "user-location-icon", source: src)
                    .iconImage(WaypointIcons.userLocation)
                    .iconAllowsOverlap(true)
                    .iconAnchor("center")
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
        // Clamp pinch-zoom to the pack's effective max so the user can't
        // pinch past the highest available tile zoom (z=10 today) into ugly
        // upscaled rectangles. Pinch-out / zoom-out stays unbounded — the
        // world skeleton renders fine at z=0. AlaskaRouter-5h4y.
        .unsafeMapViewControllerModifier { controller in
            controller.mapView.maximumZoomLevel = TilePackManifest.shared.effectiveMaxZoom

            // Ring A spike for AlaskaRouter-39eu — probe whether MapLibre's
            // native `MLNLineStyleLayer.lineOffset` is usable for the
            // multi-pass offset rendering. THROWAWAY: gated by the
            // -spikeRingA launch arg, no effect in normal app runs.
            if LaunchArgs.spikeRingA, let style = controller.mapView.style {
                ExpeditionMapView.installRingASpike(into: style)
            }
        }
    }
}
