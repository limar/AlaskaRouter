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

    /// One-call reset to v1 defaults.
    func resetToDefaults() {
        dotDiameterDefault  = Defaults.dotDiameterDefault
        dotDiameterSelected = Defaults.dotDiameterSelected
        dotFontWeight       = Defaults.dotFontWeight
        dotFontSizeRatio    = Defaults.dotFontSizeRatio
        useLooseMatcher     = Defaults.useLooseMatcher
        placeMarkerStyle    = Defaults.placeMarkerStyle
    }

    // MARK: - Init / persistence

    private init() {
        let d = UserDefaults.standard
        dotDiameterDefault  = (d.object(forKey: K.dotDiameterDefault)  as? Double) ?? Defaults.dotDiameterDefault
        dotDiameterSelected = (d.object(forKey: K.dotDiameterSelected) as? Double) ?? Defaults.dotDiameterSelected
        dotFontWeight       = (d.object(forKey: K.dotFontWeight)       as? Double) ?? Defaults.dotFontWeight
        dotFontSizeRatio    = (d.object(forKey: K.dotFontSizeRatio)    as? Double) ?? Defaults.dotFontSizeRatio
        useLooseMatcher     = (d.object(forKey: K.useLooseMatcher)     as? Bool)   ?? Defaults.useLooseMatcher
        placeMarkerStyle    = (d.object(forKey: K.placeMarkerStyle)    as? Int)    ?? Defaults.placeMarkerStyle
    }

    private enum K {
        static let dotDiameterDefault  = "tweak.dot.diameter.default"
        static let dotDiameterSelected = "tweak.dot.diameter.selected"
        static let dotFontWeight       = "tweak.dot.font.weight"
        static let dotFontSizeRatio    = "tweak.dot.font.sizeRatio"
        static let useLooseMatcher     = "tweak.search.useLooseMatcher"
        static let placeMarkerStyle    = "tweak.places.markerStyle"
    }

    enum Defaults {
        // Values converged via the in-app tweaks panel; verified on both
        // the simulator and the device. Adjust via the panel; this enum is
        // the "fresh install" / "Reset to defaults" baseline.
        static let dotDiameterDefault: Double  = 24
        static let dotDiameterSelected: Double = 27
        static let dotFontWeight: Double       = 0.50   // between .bold (0.4) and .heavy (0.56)
        static let dotFontSizeRatio: Double    = 0.54
        static let useLooseMatcher: Bool       = true   // milestone 2 on by default; flip OFF to A/B
        static let placeMarkerStyle: Int       = 1      // vyfe spike — start on Variant A (outline+halo)
    }
}
