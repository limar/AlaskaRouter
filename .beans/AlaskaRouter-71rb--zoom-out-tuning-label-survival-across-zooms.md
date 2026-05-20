---
# AlaskaRouter-71rb
title: Zoom-Out Tuning + label survival across zooms
status: in-progress
type: feature
priority: high
created_at: 2026-05-19T07:16:34Z
updated_at: 2026-05-20T18:58:02Z
parent: AlaskaRouter-xtua
---

Named v1 polish requirement. Labels for cities/peaks/key features should remain readable across zoom levels (currently world skeleton z=0-5 has terrain but minimal labels). Includes deciding which labels appear at which zooms, halo/contrast tuning, and graceful decimation when too many.

## Summary of Changes (first pass)

The bean's scope is broad — full zoom-tier label tuning is multi-session work. This first pass plugs the most obvious gap: at z=0..5 the OpenTopoMap raster has sparse/unreadable labels, so the user has no orientation when zoomed out. Added a small anchor-label vector layer on top of the raster.

`AlaskaRouter/Resources/alaska-anchor-labels.geojson` (new) — 13 hand-picked orientation features in 5 tiers:
- **region** — "ALASKA" (centroid placed in the northern interior so it doesn't conflict with the Parks Highway route corridor on the demo trip)
- **water** — "BERING SEA", "GULF OF ALASKA", "ALEUTIAN ISLANDS"
- **mountains** — "Brooks Range", "Alaska Range", "Wrangell Mtns"
- **city** — Anchorage, Fairbanks, Juneau, Nome, Bethel
- **peak** — Denali

`AlaskaRouter/Resources/style-base.json` — added a GeoJSON source and 5 SymbolStyleLayers, each with its own zoom range and text-opacity ramp:
| Tier | minzoom | maxzoom | text-size ramp | halo |
|------|---------|---------|----------------|------|
| region | 0 | 6 | 14→32 | warm-paper |
| water | 1 | 6 | 10→16 | white |
| mountains | 3 | 8 | 9→14 | warm-paper |
| city | 3 | 8 | 10→15 | warm-paper |
| peak | 4 | 8 | 10→14 | warm-paper |

The text-opacity ramps fade labels IN around their floor zoom and OUT at the ceiling, where the OpenTopoMap raster's baked OSM labels take over. Halo colors picked to read against the warm topo palette without "tech-blue" feel.

`AlaskaRouter/Map/ExpeditionMapView.swift` — extended the styleURL template-substitution pass to also resolve `__ANCHOR_LABELS_URL__` from the bundle.

## Verification

Built clean. Screenshots captured at z=2, 3, 4, 5, 6 in `/tmp/labels-z*.png` — labels appear/fade smoothly across the range. At z=6 the anchor labels yield to the raster's baked labels.

## Deferred (this bean stays in-progress for v1 polish)

The named v1 polish requirement covers a broader frontier than this pass touches. Concrete follow-ups, in roughly priority order:

1. **More anchor coverage** — only 13 features today; add more landmarks, glaciers, key waterways, more peaks (Foraker, Hayes, Iliamna...), more towns.
2. **Mid-zoom (z=6..10) label augmentation** — we currently rely entirely on OpenTopoMap raster's baked labels here. Some are tiny, some are missing for places the user cares about. Consider extracting from the existing `alaska-places.sqlite` (already in the bundle).
3. **Collision decimation** — at zoom transitions, anchor labels and raster labels can collide. SymbolStyleLayer's `text-allow-overlap: false` + `text-padding` get us partway; a manual cull at known overlap zooms would help.
4. **Tier styling polish** — letter-spacing on tracked all-caps labels is a single property today; per-feature `properties.letterSpacing` overrides exist in the GeoJSON but aren't yet wired through the style.
5. **Italics for water labels** — atlases conventionally italicize hydrographic labels. Needs a Noto Sans Italic glyph bundle (currently only `Noto Sans Regular`).
6. **Centroid + line-following labels for ranges/rivers** — Brooks Range etc would read better as gently curved labels following the feature's shape.
