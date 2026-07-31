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
// This view owns the *colour* half of that, behind the `calloutIconStyle`
// A/B tweak, so the choice can be made from the map rather than from
// argument. Size and placement stay with each caller for now — aligning them
// is a separate decision on the same bean.
//
// Style 2 borrows `PlaceIcons.color(for:)`, the palette that already tints
// the map markers, rather than inventing a second one: a stop's icon on the
// map and in its callout should not be two different colours.

import SwiftUI

struct CalloutIcon: View {
    let category: String?
    /// Glyph point size — the caller's existing value, unchanged by the tweak.
    let size: CGFloat
    /// Weight of the symbol, again the caller's existing value.
    var weight: Font.Weight = .semibold
    /// The colour this callout ships with today, used when the tweak is at
    /// style 0. Passed in because the two callouts genuinely differ.
    let shippedColor: Color

    /// PreviewCallout's existing icon colour, now available to both.
    static let slateBlue = Color(red: 0.20, green: 0.40, blue: 0.65)

    var body: some View {
        Image(systemName: CategorySymbol.name(for: category))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch TweaksStore.shared.calloutIconStyle {
        case 1:  return Self.slateBlue
        case 2:  return Color(uiColor: PlaceIcons.color(for: category ?? ""))
        default: return shippedColor
        }
    }
}
