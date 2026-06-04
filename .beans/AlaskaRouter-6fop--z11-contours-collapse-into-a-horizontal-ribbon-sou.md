---
# AlaskaRouter-6fop
title: z11 contours collapse into a horizontal ribbon south of Galbraith Lake
status: in-progress
type: bug
priority: high
created_at: 2026-06-04T14:57:06Z
updated_at: 2026-06-04T15:09:58Z
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
- [ ] Rework prepare-copernicus-contours.sh to use a geographic DEM source
- [ ] Regenerate + reimport contours; render Galbraith sample; verify no ribbon/gaps
- [ ] Full z11 rerender + export + repack + reinstall (combine with lg59 fix)
