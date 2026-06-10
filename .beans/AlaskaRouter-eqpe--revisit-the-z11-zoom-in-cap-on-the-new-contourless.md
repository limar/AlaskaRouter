---
# AlaskaRouter-eqpe
title: Revisit the z11 zoom-in cap on the new contourless base (overzoom verdict)
status: todo
type: task
created_at: 2026-06-10T15:45:01Z
updated_at: 2026-06-10T15:45:01Z
parent: AlaskaRouter-7avb
---

## Why now
[[5h4y]] capped view zoom at the pack's maxzoom (11) because overzoomed raster looked bad. That verdict was rendered on the OLD base -- white + brown contour webs + raster-only roads, the worst overzoom material. The base has since changed completely: vibrant contour-free relief ([[f7tt]]) which softens gracefully, plus crisp vector minor roads ([[levi]]) that stay sharp at ANY zoom.

## Task
- [ ] Raise view maxzoom to ~13 (raster source stays maxzoom 11 -> MapLibre overzooms it; vector overlay stays crisp), behind a quick build
- [ ] Eyeball on device at Galbraith + a town: does soft relief + sharp vector roads read as intentional (Apple-Maps-style) or as blur?
- [ ] Decide: keep 13, clamp lower, or revert to 11. Update TilePackManifest.effectiveMaxZoom logic accordingly (it currently derives the cap from pack coverage maxzoom)

## Note
If accepted, tap targets / minor-road tracing at z12-13 becomes usable -- the original Galbraith complaint fully dissolves.
