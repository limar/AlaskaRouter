// Live in-app tweaks for design iteration. Persists to UserDefaults so
// settings survive app relaunches; the values you land on become the
// defaults (the app is a personal tool — production carries these tweaks).
//
// Pattern: one shared @Observable singleton that views can read/bind to.
// Tweak changes propagate via SwiftUI's observation; the WaypointIcons
// cache keys include the tweak values so any change naturally invalidates
// the cache without a manual clear step.

import SwiftUI

@Observable
@MainActor
final class TweaksStore {
    static let shared = TweaksStore()

    // MARK: - Waypoint Dot (AlaskaRouter-ykuf)

    /// Diameter (pt) of the default (unselected) waypoint Dot.
    var dotDiameterDefault: Double {
        didSet { UserDefaults.standard.set(dotDiameterDefault, forKey: K.dotDiameterDefault) }
    }
    /// Diameter (pt) of the selected (sobresaliente) waypoint Dot.
    var dotDiameterSelected: Double {
        didSet { UserDefaults.standard.set(dotDiameterSelected, forKey: K.dotDiameterSelected) }
    }
    /// Font weight for the digit baked into the Dot icon. Maps directly to
    /// `UIFont.Weight(rawValue:)`. Named weights:
    ///   regular=0.0, medium=0.23, semibold=0.30, bold=0.40, heavy=0.56, black=0.62
    var dotFontWeight: Double {
        didSet { UserDefaults.standard.set(dotFontWeight, forKey: K.dotFontWeight) }
    }
    /// Digit font size as a fraction of the Dot's diameter. 0.55 means a
    /// 32pt Dot draws the digit at ~17.6pt. 2-digit numbers automatically
    /// scale down by 0.76 of this ratio so they still fit.
    var dotFontSizeRatio: Double {
        didSet { UserDefaults.standard.set(dotFontSizeRatio, forKey: K.dotFontSizeRatio) }
    }

    // MARK: - Search Matcher (AlaskaRouter-22h7 milestone 2)

    /// When true, the search pipeline gets two extra retry stages between
    /// "strict prefix-AND" and the edit-distance fallback:
    ///   (a) synonym-expanded — bike↔motorcycle, sign↔wayside, ferry↔ferries, …
    ///   (b) drop-droppable — strip descriptor tokens ("ferry", "sign", "the", …)
    ///       that aren't typically part of the proper name.
    /// Toggle off to compare against the original strict behavior. Defaults
    /// to ON because it strictly broadens recall (never removes a hit).
    var useLooseMatcher: Bool {
        didSet { UserDefaults.standard.set(useLooseMatcher, forKey: K.useLooseMatcher) }
    }

    // MARK: - Place markers (AlaskaRouter-vyfe spike harness)

    /// Visual treatment for the ~33k place markers rendered on the map.
    /// A spike-only Tweak so the user can A/B between variants on device
    /// before locking the design. Values:
    ///   0 — filled (iteration 3): saturated colored geometric shape baked at 16 px
    ///   1 — outline + cream halo: stroke-only colored shape on a wider cream halo
    ///       (visual coherence with the labels' thin cream halo treatment)
    ///   2 — smaller + translucent: same filled shape but 10 px @ 0.6 alpha
    var placeMarkerStyle: Int {
        didSet { UserDefaults.standard.set(placeMarkerStyle, forKey: K.placeMarkerStyle) }
    }

    /// Multiplier applied to every map-label `text-size` interpolation
    /// at runtime (label-region, label-water, label-mountains, label-city,
    /// and all places-tier-* layers). 1.0 = the values declared in
    /// style-base.json; 0.7 = noticeably smaller; 1.5 = noticeably larger.
    /// A user-facing knob because legible-font preferences vary a lot —
    /// future work may also drive this from iOS Dynamic Type.
    var labelSizeMultiplier: Double {
        didSet { UserDefaults.standard.set(labelSizeMultiplier, forKey: K.labelSizeMultiplier) }
    }

    // MARK: - Search bar Cancel button (AlaskaRouter-y7l0 spike harness)

    /// Visual treatment for the Cancel button that replaces the AK chip
    /// when the search field is focused. Spike-only Tweak — once we lock
    /// a combo on-device we strip these. Values:
    ///   0 — plain text (no chip)
    ///   1 — filled chip (white text on color fill)
    ///   2 — outlined chip (colored stroke + text, no fill)
    var cancelButtonStyle: Int {
        didSet { UserDefaults.standard.set(cancelButtonStyle, forKey: K.cancelButtonStyle) }
    }

    /// Index into the 7-color curated Cancel palette:
    ///   0 — Slate blue (0.35/0.45/0.55)        cool, muted (initial recommendation)
    ///   1 — Brand blue (0.20/0.40/0.65)        same as category-icon blue
    ///   2 — System blue (.blue)                iOS-conventional
    ///   3 — Charcoal (0.30/0.30/0.30)          neutral dark
    ///   4 — Secondary gray (Color(white: 0.55))quietest
    ///   5 — Teal (0.20/0.55/0.55)              cool with personality
    ///   6 — System red (.red)                  iOS Cancel/destructive convention (zaha)
    /// For style 1 (filled), this is the fill color. For 0 and 2, it's the
    /// text/stroke color.
    var cancelButtonColor: Int {
        didSet { UserDefaults.standard.set(cancelButtonColor, forKey: K.cancelButtonColor) }
    }

    /// Font weight for the "Cancel" label:
    ///   0=regular, 1=medium, 2=semibold, 3=bold, 4=heavy
    var cancelButtonFontWeight: Int {
        didSet { UserDefaults.standard.set(cancelButtonFontWeight, forKey: K.cancelButtonFontWeight) }
    }

    /// One-call reset to v1 defaults.
    func resetToDefaults() {
        dotDiameterDefault     = Defaults.dotDiameterDefault
        dotDiameterSelected    = Defaults.dotDiameterSelected
        dotFontWeight          = Defaults.dotFontWeight
        dotFontSizeRatio       = Defaults.dotFontSizeRatio
        useLooseMatcher        = Defaults.useLooseMatcher
        placeMarkerStyle       = Defaults.placeMarkerStyle
        labelSizeMultiplier    = Defaults.labelSizeMultiplier
        cancelButtonStyle      = Defaults.cancelButtonStyle
        cancelButtonColor      = Defaults.cancelButtonColor
        cancelButtonFontWeight = Defaults.cancelButtonFontWeight
    }

    // MARK: - Init / persistence

    private init() {
        let d = UserDefaults.standard
        dotDiameterDefault     = (d.object(forKey: K.dotDiameterDefault)     as? Double) ?? Defaults.dotDiameterDefault
        dotDiameterSelected    = (d.object(forKey: K.dotDiameterSelected)    as? Double) ?? Defaults.dotDiameterSelected
        dotFontWeight          = (d.object(forKey: K.dotFontWeight)          as? Double) ?? Defaults.dotFontWeight
        dotFontSizeRatio       = (d.object(forKey: K.dotFontSizeRatio)       as? Double) ?? Defaults.dotFontSizeRatio
        useLooseMatcher        = (d.object(forKey: K.useLooseMatcher)        as? Bool)   ?? Defaults.useLooseMatcher
        placeMarkerStyle       = (d.object(forKey: K.placeMarkerStyle)       as? Int)    ?? Defaults.placeMarkerStyle
        labelSizeMultiplier    = (d.object(forKey: K.labelSizeMultiplier)    as? Double) ?? Defaults.labelSizeMultiplier
        cancelButtonStyle      = (d.object(forKey: K.cancelButtonStyle)      as? Int)    ?? Defaults.cancelButtonStyle
        cancelButtonColor      = (d.object(forKey: K.cancelButtonColor)      as? Int)    ?? Defaults.cancelButtonColor
        cancelButtonFontWeight = (d.object(forKey: K.cancelButtonFontWeight) as? Int)    ?? Defaults.cancelButtonFontWeight
    }

    private enum K {
        static let dotDiameterDefault     = "tweak.dot.diameter.default"
        static let dotDiameterSelected    = "tweak.dot.diameter.selected"
        static let dotFontWeight          = "tweak.dot.font.weight"
        static let dotFontSizeRatio       = "tweak.dot.font.sizeRatio"
        static let useLooseMatcher        = "tweak.search.useLooseMatcher"
        static let placeMarkerStyle       = "tweak.places.markerStyle"
        static let labelSizeMultiplier    = "tweak.places.labelSizeMultiplier"
        static let cancelButtonStyle      = "tweak.cancel.style"
        static let cancelButtonColor      = "tweak.cancel.color"
        static let cancelButtonFontWeight = "tweak.cancel.fontWeight"
    }

    enum Defaults {
        // Values converged via the in-app tweaks panel; verified on both
        // the simulator and the device. Adjust via the panel; this enum is
        // the "fresh install" / "Reset to defaults" baseline.
        static let dotDiameterDefault: Double     = 24
        static let dotDiameterSelected: Double    = 27
        static let dotFontWeight: Double          = 0.50   // between .bold (0.4) and .heavy (0.56)
        static let dotFontSizeRatio: Double       = 0.54
        static let useLooseMatcher: Bool          = true   // milestone 2 on by default; flip OFF to A/B
        static let placeMarkerStyle: Int          = 3      // vyfe iteration 6 winner: translucent + halo
        static let labelSizeMultiplier: Double    = 1.0    // unchanged from style defaults
        // y7l0 spike — initial recommendations:
        //   style: 1 (filled chip) — preserves visual weight when swapping out AK
        //   color: 0 (slate blue)  — cool counterpart to warm AK/+ palette
        //   weight: 2 (semibold)   — solid but not shouting
        static let cancelButtonStyle: Int         = 1
        static let cancelButtonColor: Int         = 0
        static let cancelButtonFontWeight: Int    = 2
    }
}
