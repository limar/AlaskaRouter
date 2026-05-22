---
# AlaskaRouter-mhax
title: Reorder stops visually on the map (proper UX for diagonal routes)
status: todo
type: feature
priority: normal
created_at: 2026-05-20T08:49:20Z
updated_at: 2026-05-21T15:07:53Z
parent: AlaskaRouter-xtua
---

Reorder-by-arrow buttons were added to the stop callout (Up / Down) but pulled in this session because:

1. **Misclick risk** — Up/Down sit between Prev/Next in the toolbar. Users navigating Prev → Next frequently miss and hit Up/Down instead, silently mutating the route order.
2. **Naming is wrong for diagonal routes** — when you're traveling NE on a road, 'Up' (= earlier in the route) actually moves you 'left-down' on the screen. The vertical metaphor only makes sense in the bottom-sheet stop list, not in spatial context.
3. **No visual feedback** — when you press Up, nothing animates; the stops just teleport. Users have no confirmation the move happened.

The bottom sheet already has working drag-to-reorder, so this isn't blocking. But on-map reorder is a real expedition-planner feature once we design it right.

## Design directions to explore

- **Drag-the-marker-along-the-route**: long-press a waypoint marker, then drag forward / backward along the route line. Snapping to position-slots between adjacent stops. Animated.
- **'Earlier / Later' labels** with route-direction arrows: at render time, compute the local route bearing at this stop, draw two arrows pointing along the route in both directions, labeled 'Earlier' and 'Later'. Tap to move one slot.
- **Numbered handles**: tap a numbered '3' badge → it grows into a tappable slot picker showing positions 1..N inline. Tap a target position. Reorder + animate.
- **Floating reorder mode**: dedicated mode toggled from the callout (small 'Reorder' icon → animation lifts the marker, taps on the route insert / drop at a new position).

Animations to consider: marker scale-up on grab, route line dimming + showing slot indicators, smooth ease-in of the stop into its new position.

## Spec checklist

- [ ] Design with mock(s); pick a direction with user
- [ ] Implement (data layer is already there — swap .order between adjacent stops, save, SwiftData propagates)
- [ ] Add subtle animation (marker scale + route-line slot indicators?)
- [ ] Re-enable in the StopCallout toolbar OR add as on-map gesture
- [ ] Verify with multi-stop trip including diagonal segments
