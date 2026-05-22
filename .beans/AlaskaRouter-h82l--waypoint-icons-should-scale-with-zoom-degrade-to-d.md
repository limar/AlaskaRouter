---
# AlaskaRouter-h82l
title: Waypoint icons should scale with zoom (degrade to dots at low zoom)
status: todo
type: feature
priority: high
created_at: 2026-05-20T11:29:03Z
updated_at: 2026-05-21T15:13:06Z
parent: AlaskaRouter-xtua
---

Waypoint markers are currently pixel-constant (44pt default / 60pt selected) at all zoom levels. At low zoom (z=5-8), they obstruct the route view — five stops clustered together look like one solid blob of icon (see screenshot in user message).

Same principle as the route-line zoom interpolation (AlaskaRouter-02pm v11): scale with the map, with a floor so they stay readable when zoomed all the way out.

## Desired behavior

- High zoom (z>=12): full-detail icon (current 44pt with disc + ring + dot)
- Mid zoom (z=8-12): icon shrinks proportionally, still recognizable
- Low zoom (z<=7): degrade to a SIMPLIFIED dot (filled circle, no inner ring/dot detail) — same visual idea as 'lose the title labels when too small'
- Always thicker than the route line at the same zoom — waypoints are the punctuation, route is the prose, the punctuation should never get lost in the prose

## Likely implementation

Two options:

1. **iconSize zoom interpolation**: SymbolStyleLayer.iconSize(interpolatedBy: .zoomLevel, stops: ...) scales the existing UIImage. Same pattern as the route's lineWidth interpolation. Cheapest. Loses the 'degrade to simple dot' bit — the icon just gets smaller.

2. **Two layers with min/max zoom**: One layer with the simplified-dot icon active at z<8, one layer with the full icon active at z>=8. Cleaner aesthetically but more code. minZoomLevel / maxZoomLevel are already on LineStyleLayer in the DSL; check Symbol.

Recommendation: (1) for v1 to ship the scaling, (2) as a polish follow-up if (1) alone doesn't feel right.

- [ ] Inline-document the iconSize stops the same way the route lineWidth stops are documented (so they're a clear tweak point)
- [ ] Verify selected (sobresaliente) icon scales correctly alongside default
- [ ] Verify preview pin (search result) follows the same scaling
- [ ] Re-screenshot z=5, z=7, z=10, z=13 to confirm
