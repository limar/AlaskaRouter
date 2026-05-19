---
# AlaskaRouter-9axu
title: Double-line route highlight for second pass (return leg / shared segment)
status: todo
type: feature
priority: high
created_at: 2026-05-19T12:13:58Z
updated_at: 2026-05-19T12:13:58Z
parent: AlaskaRouter-xtua
---

When the trip route covers the same road twice (out-and-back, loops with shared spurs, return leg), the second pass should render as a visually-distinct second line so the user sees 'I'm traveling this segment twice' at a glance. Common case: drive Cantwell→Coldfoot→Cantwell, the Parks Highway south leg is on the way back.

Likely approach: parallel offset line in a slightly different shade/dash, with collision detection at the route-line level — count how many times each segment is traversed and stack visually.

Interacts with AlaskaRouter-7nxj (blocks): each itinerary block has its own color; second-pass detection should happen per-segment-pair, not per-block.

- [ ] Design the visual treatment (color/dash/offset/glow — sketch + consult)
- [ ] Detect repeated segments in the route geometry (probably at the RoutingProvider snapped-geometry level, or post-processing the line coords)
- [ ] Render the duplicate-pass overlay layer in ExpeditionMapView
- [ ] Verify with a synthetic out-and-back trip
