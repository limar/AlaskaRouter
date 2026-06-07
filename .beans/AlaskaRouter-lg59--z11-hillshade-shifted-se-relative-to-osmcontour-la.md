---
# AlaskaRouter-lg59
title: z11 hillshade shifted SE relative to OSM/contour layers
status: completed
type: bug
priority: high
created_at: 2026-06-04T14:57:06Z
updated_at: 2026-06-07T08:45:47Z
parent: AlaskaRouter-6ihk
---

## Symptom

In the self-rendered Alaska z11 layer, the hillshade relief is translated to the south-east relative to the OSM and contour layers (and relative to the upstream-scraped z6-10 tiles, so there is a visible jump at the z10->z11 seam). At Galbraith Lake (z11/68.43/-149.40), terrain that opentopomap.org places WEST of the lake appears SOUTH of the lake in our render; the west side is bare. User screenshots (Simulator vs opentopomap.org) confirm the same shapes at offset positions.

## Root-cause hypotheses (both on the projected-Mercator axis)

The DEM derivative chain lives in projected spherical-Mercator meters (prepare-copernicus-dem.sh warps to '+proj=merc +ellps=sphere +R=6378137').

1. Grid misalignment: warp-30.tif (hillshade source) and warp-60.tif (contour source) are produced by independent gdalwarp passes with no -tap (target-aligned pixels), so their origins do not share a grid and neither is guaranteed to land on true EPSG:3857 z11 tile bounds. A consistent fractional-tile origin offset would shift the rendered hillshade.
2. Datum: warping WGS84-ellipsoid Copernicus lat/lon into +ellps=sphere Mercator without a datum shift introduces a latitude-dependent northing offset, largest at 68N.

## Confirmation (needs server gdalinfo via ssh)

gdalinfo warp-30.tif / warp-60.tif / hillshade-30-jpeg.tif on sol-icomp-03 under /home/mlifshitz/tiles/AlaskaRouter; compare origins/pixel grid/extent against true z11 tile bounds for the Galbraith area. Decide fix: -tap aligned warps to 3857 tile grid, and/or correct datum handling.

## Checklist
- [ ] gdalinfo the three rasters; quantify the offset in pixels/meters
- [ ] Determine whether offset is grid-alignment, datum, or both
- [ ] Fix prepare-copernicus-dem.sh (aligned warp / datum), commit
- [ ] Re-render Galbraith sample tile, verify alignment vs opentopomap.org
- [ ] Full z11 rerender + export + repack + reinstall

See tools/opentopomap-render/RENDERING-RUNBOOK.md section 7 (Bug A).

## ROOT CAUSE CONFIRMED (2026-06-04, server gdalinfo)

The DEM rasters are warped to the WRONG Mercator sphere.

gdalinfo on /mnt/data/srtm/{warp-30,warp-60,hillshade-30-jpeg}.tif all show:
  GEOGCS["Normal Sphere (r=6370997)", SPHEROID["sphere",6370997,0]], Mercator_1SP
  Origin = (-20015077.371, 11740027.523)   # = +/- pi*6370997, i.e. R=6370997 world

OTM Mapnik style (/home/otm/opentopomap.xml) map+layer srs is:
  +proj=merc +a=6378137 +b=6378137 ... +nadgrids=@null +over   # R=6378137 (EPSG:3857)

Mapnik places the hillshade raster ASSUMING it is already in the R=6378137 map projection (no reprojection for same-srs raster layers). Our file is R=6370997, so its geotransform meters are read as if 6378137-meters -> the raster is mis-scaled (~0.112% smaller) and mis-placed.

Direction/magnitude at Galbraith (lon -149.4, lat 68.43): terrain lands ~18 km EAST and ~12 km SOUTH of the contour/OSM layers = the reported south-east shift. west-of-lake relief appears south-of-lake.

Why: prepare-copernicus-dem.sh warp uses -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m". PROJ honors +ellps=sphere (radius 6370997) and ignores +R=6378137. Server script == repo script (no divergence); fix is in the repo.

## Fix
Change all gdalwarp -t_srs to true Web Mercator. Safest: -t_srs EPSG:3857, or match OTM exactly: "+proj=merc +a=6378137 +b=6378137 +lat_ts=0 +lon_0=0 +x_0=0 +y_0=0 +k=1 +units=m +nadgrids=@null +no_defs +over". Remove +ellps=sphere. Re-warp -> regenerate derivatives (and contours from the corrected warp-60) -> rerender z11.

- [x] gdalinfo the three rasters; quantify the offset
- [x] Determine offset cause: wrong Mercator sphere (R=6370997 vs 6378137)
- [x] Fix prepare-copernicus-dem.sh srs, commit (warps now -t_srs EPSG:3857)
- [ ] Re-warp + regen derivatives; render Galbraith sample; verify alignment
- [ ] Full z11 rerender + export + repack + reinstall (combine with Bug B fix)

## POC VERIFIED (2026-06-04)

Bounded Galbraith re-render (DEM_TARGET_EXTENT=-150.2 67.8 -148.8 68.8) through the corrected pipeline on the server. gdalinfo confirms hillshade-30-jpeg.tif is now true Web Mercator (SPHEROID WGS 84 6378137, +a=6378137 +b=6378137 +nadgrids=@null). Rendered z11 tiles around Galbraith: hillshade relief now covers terrain continuously and aligns with the lake/valleys (vs sparse/misplaced in the shipped pack). Before/after 3x4 tile grid confirms the SE shift is gone. Remaining: full statewide re-render.

## Status 2026-06-04: fix committed (1aeb0cc) + Galbraith POC verified. Statewide re-render running (logs/sw-pipeline.sh on sol-icomp-03). This bean closes when the corrected statewide pack is installed in AlaskaRouter/Resources/alaska-pack.pmtiles.

## Summary of Changes
Root cause: DEM derivatives were warped to PROJ '+ellps=sphere' (R=6370997) instead of true Web Mercator (R=6378137); OpenTopoMap's Mapnik style places rasters in EPSG:3857 without reprojection, so the hillshade rendered ~18 km E / ~12 km S at 68N. Fixed by warping the four derivative rasters to -t_srs EPSG:3857 (commit 1aeb0cc). Verified via Galbraith POC, then full statewide z11 re-render (commit 37c63608) installed 2026-06-07 into AlaskaRouter/Resources/alaska-pack.pmtiles (1.04 GB, maxzoom 11). Before/after across Galbraith, Denali, Dalton/Coldfoot confirms aligned relief.
