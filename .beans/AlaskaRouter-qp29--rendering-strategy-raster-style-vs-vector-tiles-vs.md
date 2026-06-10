---
# AlaskaRouter-qp29
title: 'Rendering strategy: raster-style vs vector tiles vs alternate sources for beautiful scalable maps'
status: in-progress
type: task
priority: normal
created_at: 2026-06-09T17:43:47Z
updated_at: 2026-06-10T12:32:52Z
parent: AlaskaRouter-7avb
---

## Question
As we add zoom levels/regions and want more beauty + control, what's the right rendering architecture long-term?

## Options to investigate
1. Stay raster, improve our OTM style (vibrant high-zoom, see sibling beans). Cheapest; reuses the proven pipeline; per-variant/zoom = a render+pack.
2. VECTOR tiles (MapLibre renders client-side from vector data + a style; hillshade as a raster/terrain-RGB layer). Pros: much smaller packs, runtime restyling, runtime localization (ties to AlaskaRouter-6ihk label/name work), smooth zoom, mix vector roads/rivers/landcover with hillshade. Cons: big pipeline shift (tippecanoe/planetiler, a vector style), terrain/contours as vector or terrain-RGB. Likely the real scaling answer.
3. Smart terrain upscaling / hybrid: high-res hillshade + color-relief raster + vector overlay (roads/water/labels) composited - 'render things ourselves' for beauty without full vector.
4. Alternate/added sources (we chose OTM for beauty; only switch if a source is clearly better for our use). 

## Deliverable
A recommendation with rough effort/size/quality tradeoffs, enough to pick a direction for v2+. Note the vector-tiles option also unlocks the localization/political-naming use cases (6ihk).


## DECISION (2026-06-10): Option 3 (hybrid), roads-first
Picked **Option 3**: keep OTM's relief/hillshade as RASTER (its beauty -- and the part OTM's own vector effort is still WIP on; we deliberately do NOT vectorize the topo look). Add a VECTOR overlay for the sharp/interactive features: roads now; POIs + labels/[[6ihk]] later on the same rails.

Governing invariant that kills double-draw (a hard user constraint): **exactly one layer owns each road class.** raster=major + vector=minor (small step, no re-render) OR raster=none + vector=all (big leap, [[f7tt]] re-render). The forbidden same-class-in-both config is never built.

Two parallel tracks:
- Track A = [[f7tt]] vibrant z11 + drop contours ([[xymz]]) -- pure raster restyle; also the bootstrap / mounted-PG ([[msgi]]) exercise.
- Track B = vector minor-roads spike -> [[levi]].

NOT taking: raster z12/z13 for the MAIN pack -- [[r1cf]] stays v2 optional corridor packs.
