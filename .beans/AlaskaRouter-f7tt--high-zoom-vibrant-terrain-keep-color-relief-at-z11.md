---
# AlaskaRouter-f7tt
title: 'High-zoom vibrant terrain: keep color-relief at z11+ instead of OTM''s white topo style'
status: completed
type: feature
priority: normal
created_at: 2026-06-09T17:43:47Z
updated_at: 2026-06-10T15:44:34Z
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


## Root cause found (2026-06-10) — the exact gates to edit
The washed-out z11 is NOT a different palette: `styles-otm/basemap-relief.xml` gates `relief-500` to **z5–z8** (`&maxscale_zoom5;`..`&minscale_zoom8;`). Above z8 the style renders NO color-relief — just hillshade-30 (grain-merge 0.9, z9–17) over white + landcover. So:
- [x] Gate extension implemented: scripts/patch-otm-style-vibrant-z11.sh (idempotent, container-side, vendored snapshot untouched) + `make style` target + BOOTSTRAP note. relief-30 fallback stays an option if 500 m relief looks soft on the sample render.
- [x] Contours Layer removal in the same patch script (tested on a scratch copy: 1-line gate diff, 0 contour layers remain, XML well-formed, idempotent).
- [x] Hillshade untouched.
- [x] USER PICKED **A -- OTM's own ramp** ("A-otm one handed", 2026-06-10) from rasterio-generated previews (Galbraith + Denali windows, pipeline-faithful compositing). => NO palette change, NO gdaldem rerun: the existing relief-500.tif simply becomes visible at z9-11. z11 joins the z<=10 look exactly.

NOTE: the live style lives in the CONTAINER's /home/otm; repo third_party copy is the blueprint. Sample A/B render on the server needs ssh access (blocked this session -- ask user).

## Remaining to ship (needs the render server)
- [x] Applied on server via `make style` (idempotent rerun confirmed).
- [x] Sample render eyeballed by user ("Looks good") -> statewide z11 re-render: ~14 min total (!), 74,955 tiles, 0 errors/0 failed. Contour-free Mapnik is much faster. mbtiles = 1.1 GB (vs ~0.7 GB white -- colored relief compresses worse; JPEG lever in r1cf if needed).
- [x] Laptop: md5-verified pull, pmtiles convert+extract+merge -> 1.5 GB pack installed + verified; manifest 2026-06-10.2 (+sha256 sidecars); simulator-verified at Galbraith + Fairbanks WITH the minor-roads overlay on top.
- [x] Overzoom-cap verdict is now UNBLOCKED -> spun into its own bean (see qp29 trail).

## Summary of Changes

Shipped end-to-end on 2026-06-10: relief-500 gate z8->z11 (ramp A unchanged -- user pick from rasterio previews), contours dropped ([[xymz]]), patch script + `make style` + BOOTSTRAP; statewide z11 re-render (14 min, 74,955 tiles, clean); pack 2026-06-10.2 (1.5 GB) installed and simulator-verified with the [[levi]] vector minor-roads overlay. z11 now matches the vibrant z<=10 look. GitHub release publish deliberately left pending user GO.
