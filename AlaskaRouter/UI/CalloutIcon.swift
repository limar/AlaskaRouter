// The category icon shown in the two map callouts (AlaskaRouter-dzhp).
//
// Field report: tapping a city / airport / peak gives a coloured icon, but
// tapping a trip stop gives a grey one. That is real — the two callouts grew
// their icons independently and disagree on all three of colour, size and
// placement:
//
//                  StopCallout            PreviewCallout
//   colour         .secondary (grey)      slate blue
//   size           12 pt                  18 pt
//   placement      inline before title    22x22 leading column
//
// Colour is now settled: slate blue in both, the colour PreviewCallout
// already used.
//
// Per-category colour was built and rejected on rendered evidence. The
// obvious move — borrow `PlaceIcons.color(for:)`, which already tints the map
// markers — does not survive the move into a callout. That palette is tuned
// for the cream paper basemap, while the callout is `.thinMaterial` and picks
// up whatever map colour sits beneath it, so the warm browns go muddy on a
// green-tinted card and nearly vanish on a warm one. It fails worst on the
// commonest case: `settlement_major` is #3A2A18, deliberately near-ink so
// towns sit at the top of the paper map's label hierarchy, which in a callout
// reads as "not coloured at all" — the very complaint that opened the bean.
//
// Per-category is still possible, but it needs a callout-specific palette
// (brighter, more saturated, a real hue for settlements), not this one.
//
// Size and placement still differ between the two callouts; aligning them is
// a separate decision on the same bean.

import SwiftUI

struct CalloutIcon: View {
    let category: String?
    /// Glyph point size — the caller's existing value, unchanged by the tweak.
    let size: CGFloat
    /// Weight of the symbol, again the caller's existing value.
    var weight: Font.Weight = .semibold
    /// Override for the slate-blue default. AlaskaRouter-dzhp accent A/B:
    /// a committed stop's map pin is accentWarm, not slate blue, so the
    /// stop callout may want to echo its own pin instead.
    var tint: Color? = nil

    /// The one callout icon colour. Cool and saturated enough to hold contrast
    /// whether the material underneath picks up green tundra or warm tundra.
    static let slateBlue = Color(red: 0.20, green: 0.40, blue: 0.65)

    var body: some View {
        Image(systemName: CategorySymbol.name(for: category))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(tint ?? Self.slateBlue)
    }
}
