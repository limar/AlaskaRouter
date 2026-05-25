// Runtime label-size multiplier for the MapLibre style (AlaskaRouter-vyfe).
//
// MapLibre's text-size is declared per-layer in style-base.json as a
// zoom-interpolated stop schedule. To honor the user's TweaksStore
// `labelSizeMultiplier` we rebuild each layer's text-size expression with
// every base value multiplied by the chosen factor, then write it back
// to the layer at runtime. Called from the ExpeditionMapView's unsafe
// map-view modifier hook, guarded by a `lastAppliedMultiplier` to avoid
// re-creating the NSExpression every frame.
//
// The schedule below MUST mirror the text-size stops in style-base.json's
// label-* and places-tier-* layers. If you edit either, edit both.

import Foundation
import MapLibre

enum MapLabelSizing {

    /// Mirror of every label layer's text-size stops in style-base.json.
    /// Schedule = the list of (zoom, point-size) pairs the layer
    /// interpolates between. Update both here AND there if you tweak.
    private static let schedules: [(layerID: String, stops: [(zoom: Float, size: Float)])] = [
        // Curated anchor labels (alaska-anchor-labels.geojson)
        ("label-region",                 [(1, 14),  (4, 26),  (5, 32)]),
        ("label-water",                  [(1, 10),  (4, 14),  (5, 16)]),
        ("label-mountains",              [(3,  9),  (5, 12),  (7, 14)]),
        ("label-city",                   [(3, 10),  (5, 13),  (7, 15)]),
        // Places overlay (places.geojson)
        ("places-tier-major-settlement", [(4, 11),  (8, 13), (12, 15)]),
        ("places-tier-settlement",       [(6, 10), (10, 12), (14, 13)]),
        ("places-tier-peak",             [(7,  9), (12, 11.5)]),
        ("places-tier-natural-major",    [(7,  9), (12, 11.5)]),
        ("places-tier-misc",             [(9,  9), (13, 11)]),
        ("places-tier-long-tail",        [(11, 8.5), (16, 10.5)]),
    ]

    /// Last multiplier applied — guards re-creating NSExpressions on every
    /// hook fire. -1 = "never applied yet"; set to the new value after
    /// successful application.
    @MainActor static var lastAppliedMultiplier: Double = -1

    /// Apply the multiplier to every layer in `schedules`. Idempotent —
    /// calling with the same multiplier as last time is a no-op.
    @MainActor
    static func apply(_ multiplier: Double, to style: MLNStyle) {
        guard abs(multiplier - lastAppliedMultiplier) > 0.001 else { return }
        let mult = Float(multiplier)
        for (id, stops) in schedules {
            guard let layer = style.layer(withIdentifier: id) as? MLNSymbolStyleLayer else { continue }
            // Build the `mgl_interpolate:withCurveType:parameters:stops:`
            // NSExpression MapLibre iOS uses for its zoom-stop expressions.
            let scaledStops = NSMutableDictionary()
            for stop in stops {
                scaledStops[NSNumber(value: stop.zoom)] = NSNumber(value: stop.size * mult)
            }
            // Only override text-size; leave text-field, text-font, halo,
            // anchor, padding etc. as declared in style-base.json.
            layer.textFontSize = NSExpression(
                format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
                scaledStops
            )
        }
        lastAppliedMultiplier = multiplier
    }
}
