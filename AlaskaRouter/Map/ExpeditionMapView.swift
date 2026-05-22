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
    /// A change-detector string for the live-tweaks store (AlaskaRouter-ykuf).
    /// Held as a stored property so SwiftUI sees a value change when any
    /// tweak slider moves; that schedules `updateUIViewController`, which
    /// fires our unsafe hook with the new tweak values applied to icons.
    let tweaksFingerprint: String

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

    /// Step 4 — render each RIBBON as one polyline at its absolute
    /// lineOffset and its block color. A ribbon is a maximal run of
    /// consecutive legs sharing pass + block; one pass that crosses N
    /// blocks emits N ribbons (same offset, different colors, meeting
    /// at the block-boundary waypoint).
    ///
    /// Idempotent via per-ribbon content-fingerprint layer IDs; any
    /// change (coords / offset / color / snap-state) forces remove+re-add.
    fileprivate static func syncTripRouteLayer(
        style: MLNStyle,
        trip: Trip?,
        snappedRouteCoords: [CLLocationCoordinate2D]?
    ) {
        let ribbons: [RouteRibbon] = trip?.routeRibbons(snappedCoords: snappedRouteCoords) ?? []

        struct DesiredLayer {
            let id: String
            let ribbon: RouteRibbon
        }
        let desired: [DesiredLayer] = ribbons.map { ribbon in
            // Content fingerprint per ribbon — captures whatever could
            // visually change.
            var hasher = Hasher()
            hasher.combine(ribbon.id)
            hasher.combine(ribbon.coords.count)
            if let f = ribbon.coords.first {
                hasher.combine(Int((f.latitude * 1e5).rounded()))
                hasher.combine(Int((f.longitude * 1e5).rounded()))
            }
            if let l = ribbon.coords.last {
                hasher.combine(Int((l.latitude * 1e5).rounded()))
                hasher.combine(Int((l.longitude * 1e5).rounded()))
            }
            let mid = ribbon.coords[ribbon.coords.count / 2]
            hasher.combine(Int((mid.latitude * 1e5).rounded()))
            hasher.combine(Int((mid.longitude * 1e5).rounded()))
            hasher.combine(Int((ribbon.offsetMultiplier * 1000).rounded()))
            hasher.combine(ribbon.color)
            hasher.combine(ribbon.isStraightLineFallback)
            let h = UInt32(truncatingIfNeeded: hasher.finalize())
            return DesiredLayer(
                id: String(format: "%@%d-%08x", tripRouteLayerPrefix, ribbon.id, h),
                ribbon: ribbon
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
                coordinates: d.ribbon.coords,
                count: UInt(d.ribbon.coords.count)
            )
            let source = MLNShapeSource(identifier: srcID, shape: polyline, options: nil)
            style.addSource(source)

            let layer = MLNLineStyleLayer(identifier: d.id, source: source)
            let c = d.ribbon.color.swiftUIColor
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
            // Offset zoom-interpolated alongside width so the ribbon's
            // inner edge stays on the polyline center at every zoom.
            if d.ribbon.offsetMultiplier != 0 {
                let offsetStops = tripRouteCoreWidthStops.mapValues { $0 * d.ribbon.offsetMultiplier }
                layer.lineOffset = NSExpression(
                    format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'exponential', 1.5, %@)",
                    offsetStops as NSDictionary
                )
            }
            if d.ribbon.isStraightLineFallback {
                layer.lineDashPattern = NSExpression(forConstantValue: [2.0, 1.5])
            }

            if let below = belowLayer {
                style.insertLayer(layer, below: below)
            } else {
                style.addLayer(layer)
            }
        }
    }

    // MARK: - Waypoint icon scaling (AlaskaRouter-h82l)

    /// Zoom→multiplier stops for `iconScale`. 1.0 at z=12 keeps the
    /// existing pixel-perfect look at the user's typical planning zoom.
    /// Shrinks aggressively below z=8 so the markers stop obscuring the
    /// route line on world-/state-view zooms. Grows slightly at very
    /// high zoom so the markers stay visually present when leaning in.
    /// *** Tweak these stops to adjust marker scaling. ***
    private static let iconScaleStops: [Double: Double] = [
        5:  0.30,    // world / state view — small dot-like presence
        8:  0.55,    // route overview
        10: 0.80,    // mid-zoom planning
        12: 1.00,    // full size (matches the previous pixel-constant render)
        15: 1.20,    // leaning-in
    ]

    /// Apply the zoom-interpolated `iconScale` to every trip-marker icon
    /// layer. Runs in `unsafeMapViewControllerModifier` because
    /// MapLibreSwiftDSL doesn't expose iconScale. Idempotent — same
    /// expression assigned each frame; MapLibre handles diffing.
    /// Build and maintain the trip-marker, user-location, and preview-pin
    /// symbol layers via raw MLN API. Replaces the previous DSL-built
    /// marker layers which forced a deferred-write workaround for
    /// iconScale (causing a visible flicker on every updateUIViewController).
    ///
    /// Once a layer is created here, the DSL never touches it (it's not in
    /// parent.userLayers). iconScale is set on creation and stays put.
    /// Subsequent calls update only the underlying source's features.
    fileprivate static func syncMarkerLayers(
        style: MLNStyle,
        trip: Trip?,
        selectedWaypointID: UUID?,
        userLocation: CLLocationCoordinate2D?,
        previewCoord: CLLocationCoordinate2D?,
        previewName: String?
    ) {
        let ordered = trip?.orderedWaypoints ?? []

        // Coord-level deduplication (AlaskaRouter-ykuf). When the trip
        // revisits the same geographic coord (out-and-back trips), only
        // ONE marker is drawn per coord — the FIRST visit's. Without
        // this dedup, multiple icons stack on the same pixel and their
        // digit text overlaps into an unreadable smear.
        //
        // Exception: if the user has selected a non-first visit at a
        // shared coord, we pick that visit (the selected one) for the
        // visible marker so its "selected" styling shows.
        //
        // The displayed marker's number + block color always come from
        // the chosen waypoint — per the locked spec, first-visit-wins
        // unless selection overrides.
        var groups: [String: [Waypoint]] = [:]
        var orderedKeys: [String] = []
        for wp in ordered {
            let key = String(format: "%.6f|%.6f", wp.lat, wp.lon)
            if groups[key] == nil {
                orderedKeys.append(key)
                groups[key] = []
            }
            groups[key]!.append(wp)
        }
        let dedupedWaypoints: [Waypoint] = orderedKeys.map { key in
            let group = groups[key]!
            return group.first(where: { $0.id == selectedWaypointID }) ?? group[0]
        }

        let selectedSet = dedupedWaypoints.filter { $0.id == selectedWaypointID }
        let unselectedSet = dedupedWaypoints.filter { $0.id != selectedWaypointID }

        // Default waypoint markers.
        syncTripMarkerGroup(
            style: style,
            sourceID: "trip-markers-default",
            iconLayerID: "trip-marker-default-icons",
            labelLayerID: "trip-marker-default-labels",
            waypoints: unselectedSet,
            selected: false,
            labelFontSize: 13,
            labelOffsetY: 1.4,
            labelHaloWidth: 1.6
        )

        // Selected (sobresaliente) marker.
        syncTripMarkerGroup(
            style: style,
            sourceID: "trip-markers-selected",
            iconLayerID: "trip-marker-selected-icons",
            labelLayerID: "trip-marker-selected-labels",
            waypoints: selectedSet,
            selected: true,
            labelFontSize: 14,
            labelOffsetY: 1.8,
            labelHaloWidth: 1.8
        )

        // GPS user-location puck. Pixel-constant (no iconScale applied) so
        // it behaves like Apple Maps' blue dot.
        syncSinglePinLayer(
            style: style,
            sourceID: "user-location",
            layerID: "user-location-icon",
            iconImage: WaypointIcons.userLocation,
            coordinate: userLocation,
            extraAttributes: nil,
            applyIconScale: false
        )

        // Preview pin (search result being investigated). Scales with zoom
        // alongside the trip waypoint markers.
        syncSinglePinLayer(
            style: style,
            sourceID: "preview-pin",
            layerID: "preview-pin-icon",
            iconImage: WaypointIcons.preview,
            coordinate: previewCoord,
            extraAttributes: previewCoord != nil ? ["name": previewName ?? ""] : nil,
            applyIconScale: true
        )
    }

    /// Marker group = source + (icon layer, label layer).
    /// Each waypoint's icon is pre-rendered per (number, color, selected)
    /// with the digit baked in (UIKit bold typography, since MapLibre's
    /// glyph stack only has Regular weight — AlaskaRouter-ymw6). The
    /// feature's "iconKey" attribute references the registered image.
    ///
    /// Source's shape is updated in place on subsequent calls; layers are
    /// created once and left alone.
    private static func syncTripMarkerGroup(
        style: MLNStyle,
        sourceID: String,
        iconLayerID: String,
        labelLayerID: String,
        waypoints: [Waypoint],
        selected: Bool,
        labelFontSize: Double,
        labelOffsetY: Double,
        labelHaloWidth: Double
    ) {
        // No waypoints in this group → remove everything we own here.
        if waypoints.isEmpty {
            for id in [labelLayerID, iconLayerID] {
                if let layer = style.layer(withIdentifier: id) {
                    style.removeLayer(layer)
                }
            }
            if let src = style.source(withIdentifier: sourceID) {
                style.removeSource(src)
            }
            return
        }

        // Single-color baseline for ykuf step 1.5. Per-block coloring
        // arrives in the next step — we'll pass each waypoint's block
        // color into WaypointIcons.dot(...) instead of this constant.
        let dotColor = UIColor(red: 0.760, green: 0.255, blue: 0.047, alpha: 1.0)

        let features: [MLNPointFeature] = waypoints.map { wp in
            let numberStr = String(wp.order + 1)
            let (image, iconName) = WaypointIcons.dot(
                number: numberStr,
                color: dotColor,
                selected: selected
            )
            if style.image(forName: iconName) == nil {
                style.setImage(image, forName: iconName)
            }
            let f = MLNPointFeature()
            f.coordinate = wp.coordinate
            f.attributes = [
                "name": wp.label ?? "",
                "wpID": wp.id.uuidString,
                "stopNumber": numberStr,
                "iconKey": iconName,
            ]
            return f
        }
        let shape = MLNShapeCollectionFeature(shapes: features)

        if let existing = style.source(withIdentifier: sourceID) as? MLNShapeSource {
            // Refresh features only; layers were created on first call.
            existing.shape = shape
            return
        }

        let source = MLNShapeSource(identifier: sourceID, shape: shape, options: nil)
        style.addSource(source)

        // Icon layer — per-feature image lookup via the "iconKey" attribute.
        // Constant size (no iconScale interpolation); the Dot's small
        // footprint reads well across our z=5..15 range.
        let icon = MLNSymbolStyleLayer(identifier: iconLayerID, source: source)
        icon.iconImageName = NSExpression(forKeyPath: "iconKey")
        icon.iconAllowsOverlap = NSExpression(forConstantValue: true)
        icon.iconAnchor = NSExpression(forConstantValue: "center")
        style.addLayer(icon)

        // Name label below icon. (Digit is now inside the icon image, no
        // separate number text layer.)
        let labelDark = UIColor(red: 0.10, green: 0.07, blue: 0.04, alpha: 1.0)
        let labelHalo = UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1.0)
        let label = MLNSymbolStyleLayer(identifier: labelLayerID, source: source)
        label.text = NSExpression(forKeyPath: "name")
        label.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
        label.textFontSize = NSExpression(forConstantValue: labelFontSize)
        label.textColor = NSExpression(forConstantValue: labelDark)
        label.textHaloColor = NSExpression(forConstantValue: labelHalo)
        label.textHaloWidth = NSExpression(forConstantValue: labelHaloWidth)
        label.textAnchor = NSExpression(forConstantValue: "top")
        label.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: labelOffsetY)))
        label.textAllowsOverlap = NSExpression(forConstantValue: false)
        style.addLayer(label)
    }

    /// Single-feature pin (user location or preview). Updates the source in
    /// place if it exists; otherwise creates source + a single symbol layer.
    private static func syncSinglePinLayer(
        style: MLNStyle,
        sourceID: String,
        layerID: String,
        iconImage: UIImage,
        coordinate: CLLocationCoordinate2D?,
        extraAttributes: [String: Any]?,
        applyIconScale: Bool
    ) {
        guard let coord = coordinate else {
            if let layer = style.layer(withIdentifier: layerID) {
                style.removeLayer(layer)
            }
            if let src = style.source(withIdentifier: sourceID) {
                style.removeSource(src)
            }
            return
        }

        let feature = MLNPointFeature()
        feature.coordinate = coord
        if let attrs = extraAttributes {
            feature.attributes = attrs
        }

        if let existing = style.source(withIdentifier: sourceID) as? MLNShapeSource {
            existing.shape = feature
            return
        }

        let iconImageName = "marker-image-\(layerID)"
        if style.image(forName: iconImageName) == nil {
            style.setImage(iconImage, forName: iconImageName)
        }
        let source = MLNShapeSource(identifier: sourceID, shape: feature, options: nil)
        style.addSource(source)

        let layer = MLNSymbolStyleLayer(identifier: layerID, source: source)
        layer.iconImageName = NSExpression(forConstantValue: iconImageName)
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconAnchor = NSExpression(forConstantValue: "center")
        if applyIconScale {
            layer.iconScale = NSExpression(
                format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'exponential', 1.5, %@)",
                iconScaleStops as NSDictionary
            )
        }
        style.addLayer(layer)
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
            // ALL trip layers (route + waypoint markers + user-location +
            // preview pin) are built in the unsafeMapViewControllerModifier
            // below. The DSL doesn't expose lineOffset / iconScale, and the
            // DSL coordinator's removes-and-re-adds-every-frame behavior
            // forces a deferred-write workaround that flickers. Direct MLN
            // API in the unsafe hook gives us layer ownership and lets us
            // set those properties on creation, once, and forget.
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

            // Production route line (AlaskaRouter-3bot rebuild).
            // Renders the trip's ribbons via native MLNLineStyleLayer.lineOffset.
            // Snap polyline used when available; straight-line dashed
            // fallback otherwise.
            if let style = controller.mapView.style {
                ExpeditionMapView.syncTripRouteLayer(
                    style: style,
                    trip: trip,
                    snappedRouteCoords: snappedRouteCoords
                )
                // All marker layers via raw MLN API so we can apply
                // iconScale on layer creation (AlaskaRouter-h82l) without
                // the DSL re-adding the layer every frame and clobbering it.
                ExpeditionMapView.syncMarkerLayers(
                    style: style,
                    trip: trip,
                    selectedWaypointID: selectedWaypointID,
                    userLocation: userLocation,
                    previewCoord: previewCoord,
                    previewName: previewName
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
