---
# AlaskaRouter-qp29
title: 'Rendering strategy: raster-style vs vector tiles vs alternate sources for beautiful scalable maps'
status: todo
type: task
priority: normal
created_at: 2026-06-09T17:43:47Z
updated_at: 2026-06-09T17:43:47Z
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
