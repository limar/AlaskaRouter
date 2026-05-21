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

    // MARK: - Production route renderer (AlaskaRouter-3bot, step 1)

    /// Layer ID prefix for the production trip route line. Layers with this
    /// prefix that no longer match the current trip get pruned each frame.
    private static let tripRouteLayerPrefix = "trip-route-"
    private static let tripRouteSourcePrefix = "trip-route-src-"

    /// Width-vs-zoom stops for the route line core, in screen points. W ≈
    /// 10pt at z=10 (the spec-locked highlight width). Floor 4pt below z=8
    /// so the route stays readable on zoom-out.
    private static let tripRouteCoreWidthStops: [Double: Double] = [
        0:  4,
        8:  4,
        10: 10,
        13: 20,
        15: 36,
        17: 64,
    ]

    /// Step 2 — render each PASS as one polyline at its absolute lineOffset.
    /// A pass is a maximal run of consecutive trip legs with no direction
    /// reversal. Single-pass trips → one centered ribbon. Multi-pass trips
    /// → N parallel ribbons via native lineOffset.
    ///
    /// Idempotent via per-pass content-fingerprint layer IDs; any change
    /// (coords, offset, color, snap-state) forces remove+re-add of that
    /// pass's layer.
    fileprivate static func syncTripRouteLayer(
        style: MLNStyle,
        trip: Trip?,
        snappedRouteCoords: [CLLocationCoordinate2D]?
    ) {
        let passes: [RoutePass] = trip?.routePasses(snappedCoords: snappedRouteCoords) ?? []
        let color: TripColor = trip?.color ?? .amber

        struct DesiredLayer {
            let id: String
            let pass: RoutePass
            let color: TripColor
        }
        let desired: [DesiredLayer] = passes.map { pass in
            // Content fingerprint per pass — captures whatever could
            // visually change about this pass.
            var hasher = Hasher()
            hasher.combine(pass.id)
            hasher.combine(pass.coords.count)
            if let f = pass.coords.first {
                hasher.combine(Int((f.latitude * 1e5).rounded()))
                hasher.combine(Int((f.longitude * 1e5).rounded()))
            }
            if let l = pass.coords.last {
                hasher.combine(Int((l.latitude * 1e5).rounded()))
                hasher.combine(Int((l.longitude * 1e5).rounded()))
            }
            let mid = pass.coords[pass.coords.count / 2]
            hasher.combine(Int((mid.latitude * 1e5).rounded()))
            hasher.combine(Int((mid.longitude * 1e5).rounded()))
            hasher.combine(Int((pass.offsetMultiplier * 1000).rounded()))
            hasher.combine(color)
            hasher.combine(pass.isStraightLineFallback)
            let h = UInt32(truncatingIfNeeded: hasher.finalize())
            return DesiredLayer(
                id: String(format: "%@%d-%08x", tripRouteLayerPrefix, pass.id, h),
                pass: pass,
                color: color
            )
        }

        let wantIDs = Set(desired.map(\.id))

        // Prune any of our layers that don't match the current want set.
        // Snapshot the layer list before mutating.
        let toRemove = style.layers.filter {
            $0.identifier.hasPrefix(tripRouteLayerPrefix) && !wantIDs.contains($0.identifier)
        }
        for layer in toRemove {
            style.removeLayer(layer)
            let srcID = tripRouteSourcePrefix + String(layer.identifier.dropFirst(tripRouteLayerPrefix.count))
            if let src = style.source(withIdentifier: srcID) {
                style.removeSource(src)
            }
        }

        // Add layers for desired passes that aren't already present.
        let belowLayer: MLNStyleLayer? = waypointLayerIDs
            .compactMap { style.layer(withIdentifier: $0) }
            .first

        for d in desired {
            if style.layer(withIdentifier: d.id) != nil { continue }
            let srcID = tripRouteSourcePrefix + String(d.id.dropFirst(tripRouteLayerPrefix.count))
            let polyline = MLNPolylineFeature(
                coordinates: d.pass.coords,
                count: UInt(d.pass.coords.count)
            )
            let source = MLNShapeSource(identifier: srcID, shape: polyline, options: nil)
            style.addSource(source)

            let layer = MLNLineStyleLayer(identifier: d.id, source: source)
            let c = d.color.swiftUIColor
            layer.lineColor = NSExpression(
                forConstantValue: UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1.0)
            )
            layer.lineWidth = NSExpression(
                format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'exponential', 1.5, %@)",
                tripRouteCoreWidthStops as NSDictionary
            )
            layer.lineOpacity = NSExpression(forConstantValue: 0.85)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            // Offset zoom-interpolated alongside width so the pass's inner
            // edge stays on the polyline center at every zoom (constant
            // offset leaves a gap when the line thins out at low zoom).
            if d.pass.offsetMultiplier != 0 {
                let offsetStops = tripRouteCoreWidthStops.mapValues { $0 * d.pass.offsetMultiplier }
                layer.lineOffset = NSExpression(
                    format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'exponential', 1.5, %@)",
                    offsetStops as NSDictionary
                )
            }
            if d.pass.isStraightLineFallback {
                layer.lineDashPattern = NSExpression(forConstantValue: [2.0, 1.5])
            }

            if let below = belowLayer {
                style.insertLayer(layer, below: below)
            } else {
                style.addLayer(layer)
            }
        }
    }

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
                // Route line: built in the unsafeMapViewControllerModifier
                // below (the DSL doesn't expose native lineOffset). This
                // body block only sets up markers + interaction sources.
                // See AlaskaRouter-3bot rebuild (post-sober-geologist).

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

            // Production route line (AlaskaRouter-3bot rebuild, step 1).
            // Renders the full trip route as ONE polyline via native
            // MLNLineStyleLayer.lineOffset (offset 0 for now — no
            // multi-pass yet). Snap polyline used when available; straight-
            // line dashed fallback otherwise.
            if let style = controller.mapView.style {
                ExpeditionMapView.syncTripRouteLayer(
                    style: style,
                    trip: trip,
                    snappedRouteCoords: snappedRouteCoords
                )
            }

            // Ring A spike (AlaskaRouter-39eu). Gated by -spikeRingA.
            // Visible only in dev runs that opt in.
            if LaunchArgs.spikeRingA, let style = controller.mapView.style {
                ExpeditionMapView.installRingASpike(into: style)
            }
        }
    }
}
