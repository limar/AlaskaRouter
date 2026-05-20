---
# AlaskaRouter-71rb
title: Zoom-Out Tuning + label survival across zooms
status: in-progress
type: feature
priority: high
created_at: 2026-05-19T07:16:34Z
updated_at: 2026-05-20T19:40:26Z
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

## Open questions before continuing

The first-pass anchor labels shipped, but the broader "Zoom-Out Tuning" v1 polish requirement needs discussion before another pass. Items below are blockers; bean stays in-progress until each has a steer.

### Coverage breadth — Light steer

When expanding from the current 13 anchor features, lean toward:
- (a) "Landmarks visible from the road" — pragmatic for road-trip orientation, OR
- (b) "Everything a serious paper atlas would name" — denser, more atmospheric

### Mid-zoom (z=6..10) augmentation from `alaska-places.sqlite`

12 k places sit in the bundle's FTS5 index. Need filtering criteria to pick a subset for label-rendering. Options:
- Whitelist by category (`settlement_major` + `visitor_center` only?)
- Population threshold (data column not yet present — would need an extraction pass)
- Hand-curated subset (most work, best feel)

### Italic glyphs for water labels

Atlas convention italicizes hydrographic labels. Currently bundle only ships `Noto Sans Regular`. Cost of adding `Noto Sans Italic` ≈ 700 KB bundle size + a glyph-export run. Worth it for v1, or skip until v2?

### Line-following labels for ranges and rivers

"BROOKS RANGE" reads better gently curved along the ridge. Needs LineString geometry — either manual digitizing of ~10 key features or OSM relation extraction. Worth the data-prep for v1, or point-anchor only?

### Collision decimation at the handoff zooms (z=6..8)

Anchor labels and OpenTopoMap raster labels can collide. Three options:
- (a) Trust MapLibre's `text-allow-overlap: false` (current; doesn't see raster labels because they're baked in)
- (b) Shift anchor zoom ranges to leave a gap (e.g., anchors stop at z=5, raster takes over from z=6)
- (c) Suppress specific raster labels via custom tile rendering (much more work)

### Reference image for "good zoom-out"

Is there a specific look in mind? Paper atlas style? Apple Maps satellite at low zoom? Anything I can match against rather than guess on taste?

### Possibly out-of-bean (separate considerations)

- Route line behavior at very low zooms — currently floored at z≤8 via "good pencil line", but the broader "Zoom-Out Tuning" requirement might want this revisited.
- Whether to fade world-skeleton (z=0..5) tiles slightly to keep the route prominent at very low zooms.
