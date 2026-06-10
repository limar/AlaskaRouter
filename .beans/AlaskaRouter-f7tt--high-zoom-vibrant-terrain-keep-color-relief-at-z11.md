---
# AlaskaRouter-f7tt
title: 'High-zoom vibrant terrain: keep color-relief at z11+ instead of OTM''s white topo style'
status: todo
type: feature
priority: normal
created_at: 2026-06-09T17:43:47Z
updated_at: 2026-06-10T12:32:52Z
parent: AlaskaRouter-7avb
---

## Goal
Make our self-rendered z>=11 as beautiful as the vibrant z<=10 (color-relief terrain), rather than reproducing OTM's deliberate white-background-at-high-zoom topo style. Confirmed we CAN: we own the Mapnik style; OTM's high-zoom plainness is a style choice we can override.

## Approach to try (in the OTM Mapnik style we render)
- Keep/extend the color-relief layer (relief-* from warp-* + relief_color_text_file) to z11+ instead of letting OTM fade it out; tune opacity so roads/labels stay legible.
- Re-tune hillshade strength/zoom range for high zoom.
- Possibly thin or drop contours (see contour bean) so the vibrant relief reads cleanly.
- Ensure landcover (forest green etc., from OSM landuse) renders at high zoom for richness.
- A/B sample tiles (mountain + valley) vs public OTM z11 and vs our z10, get user taste check (show visuals).

## Risk
color-relief at high zoom can muddy detail (the reason OTM drops it). Tune opacity / blend mode (grain-merge) to keep both beauty and legibility.


## Now Track A of the [[qp29]] hybrid decision (2026-06-10)
Parallel raster track: vibrant color-relief at z11 + DROP contours ([[xymz]]). Pure raster restyle -- no road classes change owners, so NO double-draw risk. Reuses the mounted PG (skip import) => doubles as the bootstrap / recreate-safety ([[msgi]]) exercise (overnight render). In the big-leap end state this same re-render also strips ROADS from the raster so the vector overlay ([[levi]]) owns 100% of roads.
