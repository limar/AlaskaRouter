---
# AlaskaRouter-xymz
title: Investigate dropping height contours (cost vs value given hillshade)
status: completed
type: task
priority: normal
created_at: 2026-06-09T17:43:47Z
updated_at: 2026-06-10T15:44:34Z
parent: AlaskaRouter-7avb
---

## Question
Do brown height contours earn their cost? We render them mainly because OpenTopoMap does. Given we already have hillshade (terrain shape), exact-elevation contours are arguably low value for a road-trip planner.

## What to measure (A/B once the current render is done)
- RENDER time: render a sample region (e.g. a Brooks Range + a Fairbanks block) WITH vs WITHOUT the contours Mapnik layer; record the % delta. Contours are one layer; expect a moderate per-tile draw saving.
- STORAGE: pack/tile size WITH vs WITHOUT contours (contour-dense mountain tiles vs flat). Rough prior: contour-dense z11 tiles are ~17-40 KB; flat ones less. Expect ~15-30% smaller in mountains.
- GEN/PIPELINE (per NEW REGION, not per zoom): contours are generated once into the DB and reused across zoom levels, so dropping them saves the whole warp-60 + retile + phyghtmap + import chain per region (was the old bottleneck; now ~minutes with the 1.11 sidecar). Per ADDED ZOOM LEVEL the saving is render-time + tile-size only.

## Note
If we drop contours we likely want to ALSO make terrain vibrant (color-relief) at high zoom, else the white background looks empty. Pairs with the vibrant-high-zoom bean.

## Decision
Recommend: measure, then likely drop or thin contours (e.g. only major intervals) at high zoom and lean on hillshade + color-relief.

## MEASURED (2026-06-10): contours are NOT the pack-size driver
Statewide z11 mbtiles: fine+contours ~686 MB, coarse+contours 738 MB, coarse+NO-contours ~738 MB. Within noise -> contours (thin lines) add ~nothing to pack size whether fine, coarse, or absent. The pack is dominated by the HILLSHADE raster + OSM features. So: dropping/coarsening contours yields ~0 storage win. Contours' only real cost is render time + visual clutter. The lever for smaller packs (for more zoom levels) is the hillshade (resolution, PNG->JPEG) or vector tiles -- see AlaskaRouter-qp29 / r1cf. Coarsening was also a no-op for size; keep contours fine for looks unless render time matters.


## USER DECISION (2026-06-10): drop contours for v1 (a LOOK call, not size)
User: "If z11 looks like z0-z10's valleys/mountains I don't care about contours AT ALL" -- and z0-10 (relief only, no contours) is exactly the look he likes. So drop the contour layer from the z11 render for v1; lean on hillshade + vibrant color-relief ([[f7tt]]). The measured ~0 size win stands -- this is a clutter/look decision, and it also drops the whole phyghtmap/contour-import chain off the v1 path. Spot-height point markers are the useful replacement if ever wanted -- not dense brown lines. Keep the contour tooling parked; just stop running it for v1.

## Summary of Changes

Decision shipped 2026-06-10 inside [[f7tt]]'s Track A render: contours Layer removed by scripts/patch-otm-style-vibrant-z11.sh, statewide z11 re-rendered without them. Bonus finding: render time collapsed (~14 min statewide vs ~1.5 h) -- contours were the render-time cost, exactly as this bean predicted (storage ~0, render time real). Contour tooling stays parked for future spot-heights.
