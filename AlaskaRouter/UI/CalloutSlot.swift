// Where a map callout sits on screen (AlaskaRouter-svr0).
//
// Both callouts describe the pin the map has just centred, so the pin is at
// the middle of the map view. The callout floats above it.
//
// The old placement was `Spacer` / callout / `Spacer` / `Spacer` — the card
// *centred* on the upper third. That works until the card grows: every extra
// line pushed it half up and half **down**, toward the pin. Measured across
// AlaskaRouter-dzhp and -svr0, the gap between the card's bottom edge and the
// top of its pin fell from ~11pt to ~1-2pt as the title learned to wrap and
// the distance lines followed. A stop whose neighbours both had long names
// would have covered its own pin.
//
// So anchor the *bottom* edge instead. The card's bottom sits a fixed
// distance above the pin and any extra lines grow upward, into empty map,
// which is the only direction with room. The gap no longer depends on how
// tall the card happens to be.

import SwiftUI

struct CalloutSlot<Content: View>: View {
    /// Half the height of the marker this callout describes, in points — the
    /// distance from the pin's centre (screen centre) up to its top edge.
    /// Selected trip pins render at 60pt, preview pins at 44pt.
    let pinHalfHeight: CGFloat
    @ViewBuilder var content: Content

    /// Breathing room between the pin's top edge and the card's bottom edge.
    private static var gap: CGFloat { 12 }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .padding(.horizontal, 18)
            }
            .frame(
                width: geo.size.width,
                // Bottom-aligned inside a box that stops short of the pin, so
                // the card's bottom edge lands at exactly that height however
                // tall the card is.
                height: max(0, geo.size.height / 2 - pinHalfHeight - Self.gap),
                alignment: .bottom
            )
        }
    }
}
