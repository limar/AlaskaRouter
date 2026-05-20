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
// See AlaskaRouter-9634.

import SwiftUI

enum SheetPalette {
    // MARK: - Sheet surface

    /// Warm paper wash laid OVER `.thinMaterial`. The material gives the iOS
    /// blur for free; this tint shifts it from "tech-grey glass" to "warm
    /// kitchen-table paper."
    static let surfaceTint = Color(red: 252/255, green: 250/255, blue: 244/255)
        .opacity(0.30)

    /// Subtle hairline along the top edge of the sheet.
    static let surfaceTopHairline = Color.black.opacity(0.06)

    /// Drag handle.
    static let dragHandle = Color(red: 60/255, green: 50/255, blue: 20/255)
        .opacity(0.22)

    // MARK: - Text — warm sepia palette

    /// Strong text (trip name, stop name, block name).
    static let textStrong = Color(red: 26/255, green: 26/255, blue: 26/255)

    /// Captions, hints, kind subtitles.
    static let textMuted = Color(red: 60/255, green: 50/255, blue: 20/255)
        .opacity(0.55)

    /// Eyebrow / uppercase labels.
    static let textEyebrow = Color(red: 60/255, green: 50/255, blue: 20/255)
        .opacity(0.60)

    // MARK: - Stops "card" — soft white inset

    /// Card fill that wraps the stops list.
    static let cardFill = Color.white.opacity(0.55)

    /// Card border (also block-header divider).
    static let cardBorder = Color.black.opacity(0.06)

    /// Vertical separators in the stat strip.
    static let statDivider = Color.black.opacity(0.07)

    /// Subtle row separator between stops inside a block.
    static let rowDivider = Color.black.opacity(0.06)

    // MARK: - Block header strip

    /// Subtle warm wash behind a block header to set it apart from the
    /// stops nested underneath. The mock uses 0.018 but on iOS .thinMaterial
    /// that reads as zero contrast — bumping to 0.04 lands at "you can tell
    /// this is a section break without screaming about it."
    static let blockHeaderBg = Color.black.opacity(0.04)

    // MARK: - Status colors for stat strip

    /// "Ready" / OK accent — pine green.
    static let statOk = Color(red: 22/255, green: 101/255, blue: 52/255)

    /// "Warn" — burnt amber for fuel-gap-style warnings.
    static let statWarn = Color(red: 154/255, green: 52/255, blue: 18/255)

    // MARK: - Destructive accent (trash button)

    /// Warmer red than .red — picks up the paper palette.
    static let destructive = Color(red: 0.78, green: 0.32, blue: 0.20)
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
