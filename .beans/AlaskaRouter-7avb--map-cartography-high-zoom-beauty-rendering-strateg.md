---
# AlaskaRouter-7avb
title: 'Map cartography: high-zoom beauty & rendering strategy'
status: todo
type: epic
priority: normal
created_at: 2026-06-09T17:43:47Z
updated_at: 2026-06-09T17:43:47Z
parent: AlaskaRouter-ttvk
---

## Why
At z<=10 our pack uses scraped real OpenTopoMap tiles with vibrant color-relief (orange/tan elevation tint + strong shading) - the 'love my planet' beauty we chose this source for. At z>=11 (self-rendered) the look switches to a plain white background + brown contours + faint hillshade.

Investigation (2026-06-09) confirmed this is OpenTopoMap's DELIBERATE cartographic choice, not our bug and not a layer-size workaround: a same-tile comparison showed our self-rendered z11 is ~identical to public opentopomap.org z11 (both white+contours), while our z10 (real OTM) is the vibrant color-relief. OTM drops color-relief at high zoom so roads/labels stay legible under the detail.

KEY LEVERAGE: because we self-render, we are NOT bound by OTM's high-zoom choice. We can keep terrain vibrant at z11+, tune hillshade, optionally drop contours, and blend with vector roads/water/labels - a more beautiful high-zoom map than OTM ships. This epic explores how, plus the broader rendering strategy as we scale to more zooms/regions.

Children: contour cost/value, vibrant high-zoom relief, rendering-strategy (raster style vs vector tiles vs sources).
