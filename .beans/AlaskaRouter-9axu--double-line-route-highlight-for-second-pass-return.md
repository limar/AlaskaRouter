---
# AlaskaRouter-9axu
title: Double-line route highlight for second pass (return leg / shared segment)
status: completed
type: feature
priority: high
created_at: 2026-05-19T12:13:58Z
updated_at: 2026-05-19T20:03:41Z
parent: AlaskaRouter-xtua
---

When the trip route covers the same road twice (out-and-back, loops with shared spurs, return leg), the second pass should render as a visually-distinct second line so the user sees 'I'm traveling this segment twice' at a glance. Common case: drive Cantwell→Coldfoot→Cantwell, the Parks Highway south leg is on the way back.

Likely approach: parallel offset line in a slightly different shade/dash, with collision detection at the route-line level — count how many times each segment is traversed and stack visually.

Interacts with AlaskaRouter-7nxj (blocks): each itinerary block has its own color; second-pass detection should happen per-segment-pair, not per-block.

- [x] Design the visual treatment — subtle perpendicular offset, no curves, no extra color (block colors already differentiate); 1.5× core line width spacing per user spec
- [x] Detect repeated segments in the route geometry — direction-invariant road signature: subsample, quantize to ~50m grid, sort, hash. Same signature → same road
- [x] Render the duplicate-pass overlay layer in ExpeditionMapView — switched from per-block to per-segment iteration; each segment gets its own wash + core layer with pre-offset coordinates
- [x] Verify with a synthetic out-and-back trip — works at z=9 and z=11, two clearly parallel ribbons

## Summary of Changes

- TripSegments.swift (new): TripSegment value type carrying pre-offset polyline coords, color, isExtraPass flag. Trip.passOffsetSegments(snappedCoords:) does the full pipeline — split by waypoint pair, group by road signature, assign offset slot, perpendicular-shift the polyline.
- Offset distribution: N=1 centered, N=2 ±W/2, N=3 -W/0/+W, N=4 -1.5W/-0.5W/+0.5W/+1.5W, N≥5 first 4 slots spread normally and slots 5+ cap at ±2W with dashed rendering.
- Pre-offset coordinates (since MapLibreSwiftDSL doesn't expose lineOffset): perpendicular shift in coord-space, hand-tuned scaling factor (offset_pt / 70000 → degrees) so 7pt at z=10 → ~1.5× core line width.
- ExpeditionMapView: route loop now iterates Trip.passOffsetSegments, renders one (wash + core) pair per segment. Extra-pass (5th+) segments get a dash pattern.
- SampleTrip: new -seedDemoReturnLeg dev arg that appends the Parks Highway stops in reverse (excluding the final stop) to produce a synthetic out-and-back for screenshot/dev testing.

Multi-pass beyond 2 not visually verified — the dev seed only produces 2 passes. The algorithm handles 3..N+ but real test trips will exercise that.
