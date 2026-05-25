---
# AlaskaRouter-vyfe
title: Place-markers layer — render all 33k places on the map, zoom-tiered
status: todo
type: feature
priority: high
created_at: 2026-05-25T08:42:54Z
updated_at: 2026-05-25T08:42:54Z
parent: AlaskaRouter-0z7e
---

## Scope (child of AlaskaRouter-0z7e)

Render every entry from `alaska-places.sqlite` as a tappable marker on the map, gated by zoom + importance + category so the map isn't visually saturated.

## Plan

1. **Build-time export** — add a step to `build_fts5.py` (or a new sibling script) that writes `places.geojson` to `tools/build-places/data/`. One feature per row with `name`, `category`, `importance`, `admin_area` as properties. Copy into `AlaskaRouter/Resources/`.
2. **Load** — at first map appearance, the source is read from the bundle and registered as `MLNShapeSource`.
3. **Style layers** — one `MLNSymbolStyleLayer` per visibility tier with `minzoom` + `filter` on `category` / `importance`:
   - z=6+ : `settlement_major`
   - z=8+ : `settlement`, `airfield`, `visitor_center`, `ranger_station`
   - z=10+: `peak` (importance≥0.6), `glacier`, `fuel`, `park`
   - z=12+: `lake`, `viewpoint`, `attraction`, `marina`
   - z=14+: everything else
4. **Visual** — colored dot per category + label text below. Reuse SF Symbol icons baked via the `WaypointIcons.swift` pattern as a later visual upgrade (defer to `sn3r`).
5. **Hit-testing** — register the new layer IDs with `ExpeditionMapView.onTapMapGesture(on:)` so taps on these features become a place tap (see the tap-on-place sibling bean).
6. **Peak labels** — once peaks are in the new layer, the existing `label-peak` layer in `style-base.json` becomes redundant for the long tail. Keep it for the 5–10 curated headline peaks (Mount McKinley, Brooks Range, etc.) at much bigger font.

## Checklist

- [ ] places.geojson build-time export
- [ ] MLNShapeSource registration in ExpeditionMapView
- [ ] Per-tier style layers
- [ ] Per-category SF Symbol icons (Phase-2 of the visual)
- [ ] Decide curated label-peak tier survival
- [ ] Performance check: 33k features on iPhone 16 simulator + device
