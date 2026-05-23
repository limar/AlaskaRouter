// Warm-paper palette + serif font helpers for the trip bottom sheet.
//
// Pulled from design/mocks/sheet.jsx — the reference says these tokens are
// "final, pixel-perfect replication expected". Centralizing them here makes
// it cheap to nudge the whole sheet's feel without grepping for raw rgba
// literals scattered across views.
//
// Why a `.serif` design choice instead of bundling Source Serif 4:
//   - iOS ships New York as the system serif since iOS 13. `.system(design:
//     .serif)` resolves to it and carries the "atlas" feel for free.
//   - Bundling Source Serif 4 is a follow-up if the system serif ever falls
//     short. Not needed for v1.
//
// Dark-mode (AlaskaRouter-yxve): every token below is adaptive. The design
// intent in dark mode is "warm campfire-lit paper" — same hue family, just
// inverted luminance. Strong text becomes the basemap cream (#f0e8d2); the
// destructive/brand red is lifted in luminance so trash buttons actually pop
// against the dark sheet background.
//
// See AlaskaRouter-9634 and AlaskaRouter-yxve.

import SwiftUI
import UIKit

// MARK: - Adaptive color helper

/// Build a SwiftUI Color that resolves to a different UIColor per light/dark
/// trait. The closure runs on every trait-change so SwiftUI views pick up
/// the new value automatically.
private func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? dark : light
    })
}

/// Convenience for warm-paper tokens specified as RGB-bytes.
private func adaptiveRGB(
    light: (r: Int, g: Int, b: Int, a: CGFloat),
    dark:  (r: Int, g: Int, b: Int, a: CGFloat)
) -> Color {
    adaptive(
        light: UIColor(red: CGFloat(light.r)/255, green: CGFloat(light.g)/255,
                       blue: CGFloat(light.b)/255, alpha: light.a),
        dark:  UIColor(red: CGFloat(dark.r)/255,  green: CGFloat(dark.g)/255,
                       blue: CGFloat(dark.b)/255, alpha: dark.a)
    )
}

enum SheetPalette {
    // MARK: - Sheet surface

    /// Warm paper wash laid OVER `.thinMaterial`. The material gives the iOS
    /// blur for free; this tint shifts it from "tech-grey glass" to "warm
    /// kitchen-table paper" (light) or "lamp-lit page edge" (dark).
    static let surfaceTint: Color = adaptiveRGB(
        light: (252, 250, 244, 0.30),
        dark:  ( 60,  50,  20, 0.20)
    )

    /// Subtle hairline along the top edge of the sheet.
    static let surfaceTopHairline: Color = adaptive(
        light: UIColor.black.withAlphaComponent(0.06),
        dark:  UIColor(red: 240/255, green: 232/255, blue: 210/255, alpha: 0.10)
    )

    /// Drag handle.
    static let dragHandle: Color = adaptive(
        light: UIColor(red: 60/255, green: 50/255, blue: 20/255, alpha: 0.22),
        dark:  UIColor(red: 240/255, green: 232/255, blue: 210/255, alpha: 0.30)
    )

    // MARK: - Text — warm sepia palette

    /// Strong text (trip name, stop name, block name).
    static let textStrong: Color = adaptiveRGB(
        light: ( 26,  26,  26, 1.0),
        dark:  (240, 232, 210, 1.0)         // basemap cream
    )

    /// Captions, hints, kind subtitles.
    static let textMuted: Color = adaptive(
        light: UIColor(red: 60/255, green: 50/255, blue: 20/255, alpha: 0.55),
        dark:  UIColor(red: 212/255, green: 200/255, blue: 168/255, alpha: 0.78)
    )

    /// Eyebrow / uppercase labels.
    static let textEyebrow: Color = adaptive(
        light: UIColor(red: 60/255, green: 50/255, blue: 20/255, alpha: 0.60),
        dark:  UIColor(red: 212/255, green: 200/255, blue: 168/255, alpha: 0.65)
    )

    // MARK: - Stops "card" — soft white inset

    /// Card fill that wraps the stops list.
    static let cardFill: Color = adaptive(
        light: UIColor.white.withAlphaComponent(0.55),
        dark:  UIColor(red: 50/255, green: 40/255, blue: 18/255, alpha: 0.40)
    )

    /// Card border (also block-header divider).
    static let cardBorder: Color = adaptive(
        light: UIColor.black.withAlphaComponent(0.06),
        dark:  UIColor(red: 240/255, green: 232/255, blue: 210/255, alpha: 0.10)
    )

    /// Vertical separators in the stat strip.
    static let statDivider: Color = adaptive(
        light: UIColor.black.withAlphaComponent(0.07),
        dark:  UIColor(red: 240/255, green: 232/255, blue: 210/255, alpha: 0.10)
    )

    /// Subtle row separator between stops inside a block.
    static let rowDivider: Color = adaptive(
        light: UIColor.black.withAlphaComponent(0.06),
        dark:  UIColor(red: 240/255, green: 232/255, blue: 210/255, alpha: 0.08)
    )

    // MARK: - Block header strip

    /// Subtle warm wash behind a block header to set it apart from the
    /// stops nested underneath. The mock uses 0.018 but on iOS .thinMaterial
    /// that reads as zero contrast — bumping to 0.04 lands at "you can tell
    /// this is a section break without screaming about it."
    static let blockHeaderBg: Color = adaptive(
        light: UIColor.black.withAlphaComponent(0.04),
        dark:  UIColor(red: 240/255, green: 232/255, blue: 210/255, alpha: 0.06)
    )

    // MARK: - Status colors for stat strip

    /// "Ready" / OK accent — pine green (light) / brighter green (dark).
    static let statOk: Color = adaptiveRGB(
        light: ( 22, 101,  52, 1.0),
        dark:  ( 60, 170,  90, 1.0)
    )

    /// "Warn" — burnt amber (light) / brighter amber (dark).
    static let statWarn: Color = adaptiveRGB(
        light: (154,  52,  18, 1.0),
        dark:  (240, 120,  40, 1.0)
    )

    // MARK: - Destructive / warm-brand accent

    /// Warm red — used for trash buttons (TripBottomSheet, StopCallout),
    /// the active-trip checkmark, the search "+" fast-add chip, and the
    /// "Removed" toast accent. In dark mode the luminance is lifted so the
    /// button stays divisible against the warm-sepia dark sheet.
    static let destructive: Color = adaptiveRGB(
        light: (199,  82,  51, 1.0),         // approx 0.78/0.32/0.20
        dark:  (225,  90,  58, 1.0)
    )

    // MARK: - Numbered-pip outer ring (dark-mode only)

    /// In dark mode, the colored block-stroke around the numbered pip blends
    /// into the warm-sepia sheet background (hue luminance collision). A
    /// thin cream ring just outside the colored stroke lifts the whole pip
    /// off the sheet. In light mode this is `.clear` (no extra ring needed).
    static let pipOuterRing: Color = adaptive(
        light: UIColor.clear,
        dark:  UIColor(red: 240/255, green: 232/255, blue: 210/255, alpha: 0.55)
    )
}

// MARK: - Typography

extension Font {
    /// Serif tier used for trip name, block name, stop name. Resolves to New
    /// York on iOS 13+ via the .serif design hint.
    static func sheetSerif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Sans tier (SF) used for eyebrows, labels, hints, button text.
    static func sheetSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}
