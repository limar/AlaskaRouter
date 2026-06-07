---
# AlaskaRouter-6fop
title: z11 contours collapse into a horizontal ribbon south of Galbraith Lake
status: in-progress
type: bug
priority: high
created_at: 2026-06-04T14:57:06Z
updated_at: 2026-06-07T09:13:47Z
parent: AlaskaRouter-6ihk
---

## Symptom

In the self-rendered Alaska z11 layer, brown contour lines south of Galbraith Lake pile into one dense horizontal band (a ribbon) with NO contour lines at all below that band - the lines from a wide latitude range are compressed onto roughly one latitude. User screenshot (third image in the session) shows the ribbon clearly.

## Root-cause hypothesis

phyghtmap is designed for GEOGRAPHIC (EPSG:4326) DEMs and emits OSM lat/lon, but prepare-copernicus-contours.sh runs it on the PROJECTED spherical-Mercator warp-60.tif, after cutting it into 5000px retile chunks (gdal_retile.py). Fed Mercator meters, phyghtmap's coordinate handling degenerates - most likely at a tile seam - squishing one tile's contours onto a single latitude band, with the area that should sit below left empty. Upstream OpenTopoMap generates contours from the geographic DEM, not the Mercator warp; that is the deviation to undo.

## Confirmation / fix direction (needs server via ssh)

- Inspect a generated contour PBF/OSM near the affected latitude; check node lat/lon vs the source tile's projected extent.
- Confirm whether phyghtmap reprojects the input or assumes geographic.
- Likely fix: generate contours from a geographic (EPSG:4326) DEM (e.g. warp Copernicus to lat/lon at the contour-resolution, or run phyghtmap on the raw Copernicus COGs / a 4326 warp) instead of the Mercator warp-60.tif. Keep the chunking/bounded-node settings that solved the 1 GiB osm2pgsql allocation failure.

## Checklist
- [ ] Inspect generated contour coordinates vs source tile extent; confirm the projection mismatch
- [ ] Decide geographic-DEM contour source; adjust prepare-copernicus-contours.sh
- [ ] Regenerate contours for the affected area, re-import, render Galbraith sample, verify no ribbon
- [ ] Full z11 contour regen + rerender + export + repack + reinstall

See tools/opentopomap-render/RENDERING-RUNBOOK.md section 7 (Bug B).

## SYMPTOM CONFIRMED IN DATA (2026-06-04, server PostGIS query)

Queried the contours DB (planet_osm_line, SRID 3857) directly on sol-icomp-03. Latitude histogram of contour lines over lon -153..-147 (6 degrees wide), 0.05deg bins:

  lat 67.30: 20833
  lat 67.35: 51296   <- dense ribbon spike
  lat 67.40: 42888
  lat 67.45: 37949
  lat 67.50: 27168
  lat 67.55: 13256
  lat 67.60: 2475
  lat 67.85-67.95: 0  <- EMPTY stripe (spans all 6 deg of longitude)
  lat 68.00-68.05: 2
  lat 68.10: 1427
  lat 68.20-68.30: 0  <- EMPTY stripe
  lat 68.35: 19735   <- another spike (Galbraith Lake band)
  lat 68.40-68.50: ~10k each
  lat 68.55+: drops to hundreds

A 6deg-wide, ~0.15deg-tall latitude stripe of mountainous Alaska with ZERO contour lines, adjacent to a band with 51k lines, cannot be real terrain. This confirms the user-reported 'ribbon + nothing below it' is in the contour DATA, not the renderer.

## Root cause (high confidence)

Systematic artifact from generating contours on the PROJECTED spherical-Mercator warp-60.tif (prepare-copernicus-contours.sh runs phyghtmap on the retiled Mercator raster). phyghtmap is built for GEOGRAPHIC (EPSG:4326) DEMs; fed Mercator meters, the non-linear Mercator latitude axis is sampled incorrectly so contours accumulate into dense horizontal bands at some latitudes and vanish at others. Same root family as AlaskaRouter-lg59 (DEM work done in projected Mercator).

Sub-mechanism to confirm during fix: geometry distortion vs dropped sub-tiles. Either way the fix removes the deviation.

## Fix
Generate contours from a GEOGRAPHIC (EPSG:4326) DEM, as upstream OpenTopoMap does. The raw Copernicus GLO-30 COGs are already EPSG:4326 -> run phyghtmap on those (or a 4326 VRT/warp at contour resolution), NOT on warp-60.tif. Keep the bounded chunking that solved the osm2pgsql 1 GiB allocation failure.

- [x] Confirm symptom is in contour data (empty stripes across 6deg longitude)
- [ ] Confirm sub-mechanism (distortion vs dropped tiles) while implementing
- [x] Make the contour source geographic: warp-60.tif now built as EPSG:4326 in prepare-copernicus-dem.sh (contours.sh unchanged; phyghtmap auto-detects CRS)
- [ ] Regenerate + reimport contours; render Galbraith sample; verify no ribbon/gaps
- [ ] Full z11 rerender + export + repack + reinstall (combine with lg59 fix)

## POC VERIFIED (2026-06-04)

warp-60.tif rebuilt as EPSG:4326 geographic; contours regenerated via phyghtmap produced 12 contiguous latitude sub-bands (67.80->68.80, no gaps). Reimported into a recreated contours DB (33,457 rows for the bounded area). Rendered z11 Galbraith tiles: the orange horizontal contour ribbon south of the lake is GONE; contours distribute normally. Before/after grid confirms. Remaining: full statewide contour regen + re-render.

## Status 2026-06-04: fix committed (1aeb0cc) + Galbraith POC verified. Statewide re-render running. Closes when the corrected statewide pack is installed.

## Summary of Changes
Root cause: contours were generated by phyghtmap from the PROJECTED Mercator warp-60.tif; the non-linear latitude axis collapsed contours into dense/empty horizontal bands (confirmed in PostGIS: empty stripes across 6deg of longitude). Fixed by building warp-60.tif as geographic EPSG:4326 (Copernicus-native) so phyghtmap gets the input it expects (commit 1aeb0cc). Verified via Galbraith POC, then full statewide re-render (37c63608) installed 2026-06-07. Before/after confirms the orange contour ribbon is gone across Galbraith-south and Dalton.

## REOPENED 2026-06-07 — statewide contour regression
Simulator inspection of the installed statewide pack: contours are MISSING in most tiles (clean hillshade only) and GARBAGE (squashed ribbons + spidernets) in specific tiles, with visible source-tile borders. Around Vi Creek / Over Creek (Dalton corridor) and south. The bounded Galbraith POC was clean, so the regression is in the STATEWIDE retile + per-tile phyghtmap ID allocation (CONTOUR_ID_STRIDE) and/or the batched import — not the projection (hillshade is correct). Hillshade (lg59) stays fixed. Diagnosing.

## ROOT CAUSE (statewide), 2026-06-07
Node-ID collision. prepare-copernicus-contours.sh gives each retile source tile a disjoint ID range of width CONTOUR_ID_STRIDE=5,000,000, but measured max nodes/source-tile = 47.2M (69 of 180 tiles exceed 5M; 1.56B nodes total). Dense tiles' IDs overrun into neighbours' ranges; osm2pgsql --append overwrites those nodes, so ways point at wrong coordinates -> spidernets where displaced nodes cluster, and apparent 'missing' contours elsewhere. DB had 11.7M lines (not missing) but with corrupted geometry. The Galbraith POC was clean only because it was a single tile (no neighbour to collide with).

## FIX
Raised ID_STRIDE default to 100,000,000 (>2x the 47.2M max). Keep --flat-nodes (-> ~143 GB flat-nodes file, fits the server). Re-generate contours (reuse existing retile tiles), re-import (--recreate), re-render z11, re-export/pack/install. DEM/hillshade are correct and unchanged (lg59 stays fixed) so the DEM stage is skipped.

- [ ] Re-generate contours with stride 100M (delete stale contours-sw PBFs, reuse contour-tiles-sw)
- [ ] Re-import (--recreate) + verify no ID overrun (maxid per tile < next start)
- [ ] Re-render z11 + export + pack + merge + install
- [ ] Simulator verify: normal contours present, no spidernet, at Vi Creek / Over Creek
