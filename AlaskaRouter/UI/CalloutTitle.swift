// The place-name title used by the map callouts (AlaskaRouter-dzhp).
//
// Long Alaska names ("Arctic Interagency Visitor Center", "Galbraith Lake
// Campground") were being cut mid-word by a hard one-line limit, so the
// callout often could not tell you which stop you were looking at.
//
// Two-step rule, decided from rendered evidence in spikes/D_callout:
//   1. One line at full size whenever the name fits. Short names are the
//      common case and must not pay for the long ones.
//   2. Otherwise drop to 75% and wrap up to four lines, ellipsizing the
//      last. 75% rather than 85% because 85% was measured to take the same
//      number of lines as no shrink at all — it costs type size and buys no
//      vertical space.
//
// Two things here are load-bearing and look redundant if you don't know the
// measurements behind them:
//
//   * `fixedSize(horizontal: false, vertical: true)` on the wrapping
//     candidate. Without it `lineLimit` silently does nothing in the callout
//     layout — the title stays on one line and truncates exactly as before.
//     A "fix" without this line renders pixel-identical to the bug.
//   * `fixedSize()` (both axes) on the single-line candidate. That is what
//     makes its ideal width the full string, which is how ViewThatFits knows
//     to reject it. Without it the candidate always "fits" and step 2 is
//     unreachable.
//
// Callers must use `.firstTextBaseline` alignment on the row holding the
// category icon; on a wrapped title a centre-aligned icon drifts to the
// vertical middle and reads as detached from the name.

import SwiftUI

struct CalloutTitle: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight

    /// Shrink applied only once the name has left a single line.
    private static let fallbackScale: CGFloat = 0.75
    /// Enough lines that the ellipsis is a guard rather than a routine
    /// outcome — nothing in a real trip has come close to four.
    private static let fallbackLineLimit = 4

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label(size)
                .lineLimit(1)
                .fixedSize()
            label(size * Self.fallbackScale)
                .lineLimit(Self.fallbackLineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ pointSize: CGFloat) -> Text {
        Text(text)
            .font(.system(size: pointSize, weight: weight))
            .foregroundStyle(.primary)
    }
}
