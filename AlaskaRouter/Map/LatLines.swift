// Runtime look-and-feel applier for the reference latitude lines —
// Arctic Circle (66.5634°N) and Equator (0°) — AlaskaRouter-cv05.
//
// Each line and each label is drawn as a CASING + CORE pair so it stays
// legible over wildly different backgrounds (deep ocean vs desert vs
// mountain): a wider, soft, light casing underneath + a narrower dark core
// on top. The pair is self-contrasting — the dark core wins on light
// ground, the light casing wins on dark ground — which is the standard
// cartographic answer (deterministic, no per-pixel blend tricks).
//
// Layers (declared statically in style-base.json):
//   lat-line-{kind}-casing   light, wider, under
//   lat-line-{kind}          dark, narrower, over
//   lat-label-{kind}-halo    light "casing" for the text, under
//   lat-label-{kind}         dark text, dark same-color halo (= pseudo-bold
//                            weight knob, since only Regular glyphs ship), over
//
// This applier mirrors MapLabelSizing: called from ExpeditionMapView's
// unsafe map-view modifier hook, fingerprint-guarded so the NSExpressions
// are only rebuilt when a TweaksStore value actually changes.
//
// The DEFAULTS here MUST mirror the static values in style-base.json.

import UIKit
import MapLibre

enum LatLines {

    // MARK: - Constants

    /// Warm cream used for both line casings and label halos. Matches the
    /// existing anchor-label halo treatment.
    private static let casingColor = UIColor(red: 1.0, green: 0.973, blue: 0.922, alpha: 0.85)
    private static let labelCasingColor = UIColor(red: 1.0, green: 0.973, blue: 0.922, alpha: 0.9)

    /// How much wider the casing is than the core (pt, total — split both sides).
    private static let casingExtraWidth: Double = 2.2

    // MARK: - Curated palettes (indexed by TweaksStore.lat*Color)

    /// Earth/sepia candidates for the Arctic Circle core + label.
    /// Index 3 (charcoal brown) is the static default in style-base.json —
    /// a saturated sepia washes out on the vibrant OpenTopoMap relief, so
    /// the core wants to be genuinely dark; the cream casing carries the
    /// contrast on dark ground.
    static let arcticPalette: [(name: String, color: UIColor)] = [
        ("Sepia",          UIColor(red: 0.478, green: 0.369, blue: 0.169, alpha: 1)), // #7a5e2b
        ("Ochre",          UIColor(red: 0.604, green: 0.482, blue: 0.247, alpha: 1)), // #9a7b3f
        ("Rust",           UIColor(red: 0.541, green: 0.294, blue: 0.169, alpha: 1)), // #8a4b2b
        ("Charcoal brown", UIColor(red: 0.290, green: 0.231, blue: 0.169, alpha: 1)), // #4a3b2b
        ("Olive",          UIColor(red: 0.420, green: 0.420, blue: 0.169, alpha: 1)), // #6b6b2b
    ]

    /// Greys for the Equator core + label. Index 3 (charcoal) is the static
    /// default — same reasoning: the core wants to be dark.
    static let equatorPalette: [(name: String, color: UIColor)] = [
        ("Soft grey",  UIColor(red: 0.541, green: 0.510, blue: 0.459, alpha: 1)), // #8a8275
        ("Cool grey",  UIColor(red: 0.494, green: 0.518, blue: 0.533, alpha: 1)), // #7e8488
        ("Light grey", UIColor(red: 0.659, green: 0.639, blue: 0.604, alpha: 1)), // #a8a39a
        ("Charcoal",   UIColor(red: 0.353, green: 0.337, blue: 0.306, alpha: 1)), // #5a564e
    ]

    /// Core dash pattern (in core-line-width units), indexed by
    /// TweaksStore.latDashStyle. nil ⇒ solid. Index 3 (dotted) is the
    /// static default in style-base.json.
    static func coreDash(_ index: Int) -> [Double]? {
        switch index {
        case 1:  return [3, 3]        // fine dash
        case 2:  return [6, 4]        // atlas dash
        case 3:  return [1, 2]        // dotted (round caps make these dots)
        default: return nil           // 0 — solid
        }
    }

    static let dashNames = ["Solid", "Fine dash", "Atlas dash", "Dotted"]

    /// Label BASE text-size stops (multiplier = 1.0). The runtime applier
    /// multiplies these by TweaksStore.latLabelSizeMultiplier. With the
    /// default multiplier (1.25) this reproduces the static values declared
    /// in style-base.json's lat-label-* layers.
    private static let labelSizeStops: [(zoom: Float, size: Float)] =
        [(3, 10), (6, 12), (10, 13)]

    /// Equator label opacity curve — mirrors style-base.json. Restored when
    /// the label is re-enabled (no label at z0/z1; fades in by z2).
    private static let equatorLabelOpacityStops: [(zoom: Float, opacity: Float)] =
        [(0, 0.0), (1, 0.0), (2, 0.85), (22, 0.85)]

    // MARK: - Apply

    /// Last-applied fingerprint — guards rebuilding NSExpressions on every
    /// hook fire. Empty = never applied yet.
    @MainActor private static var lastFingerprint = ""

    @MainActor
    static func apply(_ t: TweaksStore, to style: MLNStyle) {
        let fp = "\(t.latArcticColor)|\(t.latEquatorColor)|\(t.latLineWidth)|\(t.latDashStyle)|\(t.latLabelSizeMultiplier)|\(t.latLabelWeight)|\(t.latLabelSpacing)|\(t.latEquatorLabelEnabled)"
        guard fp != lastFingerprint else { return }

        let arctic = arcticPalette[clamp(t.latArcticColor, arcticPalette.count)].color
        let equator = equatorPalette[clamp(t.latEquatorColor, equatorPalette.count)].color

        applyLine(kind: "arctic", core: arctic, t: t, style: style)
        applyLine(kind: "equator", core: equator, t: t, style: style)

        let sizeExpr = scaledSizeExpression(t.latLabelSizeMultiplier)
        applyLabel(kind: "arctic", core: arctic, sizeExpr: sizeExpr,
                   opacityExpr: nil, t: t, style: style)
        // Equator label opacity is always set explicitly so toggling the
        // label off (constant 0) and back on (restore the zoom curve) both work.
        applyLabel(kind: "equator", core: equator, sizeExpr: sizeExpr,
                   opacityExpr: t.latEquatorLabelEnabled
                       ? equatorLabelOpacityExpression()
                       : NSExpression(forConstantValue: 0.0),
                   t: t, style: style)

        lastFingerprint = fp
    }

    // MARK: - Per-pair appliers

    @MainActor
    private static func applyLine(kind: String, core: UIColor, t: TweaksStore, style: MLNStyle) {
        let coreW = t.latLineWidth
        let casingW = coreW + casingExtraWidth
        let coreDashUnits = coreDash(t.latDashStyle)
        // Match dash pixels between core and casing: a dash is in the
        // layer's OWN width units, so to keep the casing dots aligned with
        // (and slightly larger than) the core dots, scale by coreW/casingW.
        let casingDashUnits = coreDashUnits.map { d in d.map { $0 * coreW / casingW } }

        if let layer = style.layer(withIdentifier: "lat-line-\(kind)") as? MLNLineStyleLayer {
            layer.lineColor = NSExpression(forConstantValue: core)
            layer.lineWidth = NSExpression(forConstantValue: coreW)
            layer.lineDashPattern = coreDashUnits.map { NSExpression(forConstantValue: $0) }
        }
        if let layer = style.layer(withIdentifier: "lat-line-\(kind)-casing") as? MLNLineStyleLayer {
            layer.lineColor = NSExpression(forConstantValue: casingColor)
            layer.lineWidth = NSExpression(forConstantValue: casingW)
            layer.lineDashPattern = casingDashUnits.map { NSExpression(forConstantValue: $0) }
        }
    }

    @MainActor
    private static func applyLabel(
        kind: String, core: UIColor, sizeExpr: NSExpression,
        opacityExpr: NSExpression?, t: TweaksStore, style: MLNStyle
    ) {
        let weight = t.latLabelWeight
        let spacingExpr = NSExpression(forConstantValue: t.latLabelSpacing)
        // Core: dark text + dark same-color halo. The halo width is the
        // pseudo-bold "weight" (true bold glyphs aren't bundled offline).
        if let layer = style.layer(withIdentifier: "lat-label-\(kind)") as? MLNSymbolStyleLayer {
            layer.textColor = NSExpression(forConstantValue: core)
            layer.textHaloColor = NSExpression(forConstantValue: core)
            layer.textHaloWidth = NSExpression(forConstantValue: weight)
            layer.textFontSize = sizeExpr
            layer.symbolSpacing = spacingExpr
            if let op = opacityExpr { layer.textOpacity = op }
        }
        // Halo casing: cream text + wider cream halo → the light outline
        // that keeps the dark text legible over dark ground.
        if let layer = style.layer(withIdentifier: "lat-label-\(kind)-halo") as? MLNSymbolStyleLayer {
            layer.textColor = NSExpression(forConstantValue: labelCasingColor)
            layer.textHaloColor = NSExpression(forConstantValue: labelCasingColor)
            layer.textHaloWidth = NSExpression(forConstantValue: weight + 1.4)
            layer.textFontSize = sizeExpr
            layer.symbolSpacing = spacingExpr
            if let op = opacityExpr { layer.textOpacity = op }
        }
    }

    // MARK: - Helpers

    private static func clamp(_ i: Int, _ count: Int) -> Int { min(max(i, 0), count - 1) }

    private static func scaledSizeExpression(_ multiplier: Double) -> NSExpression {
        let mult = Float(multiplier)
        let stops = NSMutableDictionary()
        for s in labelSizeStops {
            stops[NSNumber(value: s.zoom)] = NSNumber(value: s.size * mult)
        }
        return NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            stops
        )
    }

    private static func equatorLabelOpacityExpression() -> NSExpression {
        let stops = NSMutableDictionary()
        for s in equatorLabelOpacityStops {
            stops[NSNumber(value: s.zoom)] = NSNumber(value: s.opacity)
        }
        return NSExpression(
            format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
            stops
        )
    }
}
