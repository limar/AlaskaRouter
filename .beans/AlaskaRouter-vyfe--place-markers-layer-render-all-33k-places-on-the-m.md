---
# AlaskaRouter-vyfe
title: Place-markers layer — render all 33k places on the map, zoom-tiered
status: in-progress
type: feature
priority: high
created_at: 2026-05-25T08:42:54Z
updated_at: 2026-05-25T13:53:37Z
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


## Decisions inherited from the umbrella (2026-05-25)

- Bundle `places.geojson` into `AlaskaRouter/Resources/` at build time.
- V1 visual: per-category colored dot + label text below. SF Symbol icons / hand-drawn bullets are follow-up polish (the latter tracked as `sn3r`).
- Retire the existing `label-peak` style layer in `style-base.json` as part of this bean — its 13 anchor labels are subsumed by the new layer's peak-at-z=10 tier.

Ready to implement when the user says go.


## Summary of Changes (initial — rendering only; tap-dispatch is 5gmw's scope)

**Build pipeline (`build_fts5.py`):**
- After writing pois.sqlite, dump the same deduped rows to `data/places.geojson` as a `FeatureCollection` of `Point` features. Properties carry `name`, `category`, `importance`, `source`, `admin_area` — the minimum the MapLibre style + future tap handler need.
- Output: 33,470 features → 6.7 MB compact JSON. Bundled as `AlaskaRouter/Resources/places.geojson`.

**Style (`style-base.json`):**
- New source `places` referencing `__PLACES_URL__` (substituted at runtime).
- Five zoom tiers, each a circle layer + matching label layer:
  - **z=6+** `places-tier-major-settlement` — `settlement_major` (Anchorage, Fairbanks, Juneau)
  - **z=8+** / **z=9+** `places-tier-settlement` — `settlement`, `airfield`, `visitor_center`, `ranger_station`
  - **z=10+** `places-tier-natural-major` — `peak` / `glacier` / `park` / `fuel` with `importance ≥ 0.6`
  - **z=12+** / **z=13+** `places-tier-misc` — `lake`, `viewpoint`, `attraction`, `marina`
  - **z=14+** `places-tier-long-tail` — everything else
- Per-category colors (warm-paper-friendly palette) via `["match", ["get", "category"], ...]`.
- Cream stroke on each circle, halo on each label.
- **Retired** the old `label-peak` style layer (its 13 curated anchor labels were superseded — Mt McKinley, Brooks Range, etc. all surface via the new `places-tier-natural-major` tier at z=10+).

**Swift (`ExpeditionMapView.swift`):**
- Bundle URL for `places.geojson` resolved + `__PLACES_URL__` substituted in the style template.

## What's NOT in this bean

- **Tap dispatch** — `5gmw`'s scope. The layer IDs are stable and discoverable for that bean to use:
  `places-tier-major-settlement`, `places-tier-settlement`, `places-tier-natural-major`, `places-tier-misc`, `places-tier-long-tail`.
- **PlacePreviewCallout** view — `5gmw`'s scope.

- [x] places.geojson build-time export
- [x] MLNShapeSource registration via the style template (no Swift glue needed beyond placeholder substitution)
- [x] Per-tier style layers
- [x] label-peak retired
- [ ] Per-category SF Symbol icons (deferred — visual polish via `sn3r`)
- [ ] On-device visual check: markers appear at expected zooms, not visually overwhelming, trip waypoints still render on top

## Next bean: AlaskaRouter-5gmw

Wire `.onTapMapGesture(on:)` to include the five new layer IDs, dispatch to a new `PlacePreviewCallout`, hook up "+ Add to trip" via SmartInsert.


## Gotcha (2026-05-25)

`AlaskaRouter/Resources/` is a *group* path in `project.yml`, not a folder reference. New files in `Resources/` aren't auto-picked-up by Xcode — `xcodegen generate` must be re-run BEFORE the next build. Otherwise the build succeeds but the resource is missing at runtime and any `Bundle.main.url(forResource:)` lookup fatalError-s.

The `glyphs/` path IS `type: folder` (folder reference) — those work without regen. Only the group paths need the dance.

**Rule of thumb:** any time we add a file to `AlaskaRouter/Resources/`, `AlaskaRouter/Assets.xcassets/`, or any code subdirectory tracked as a group, run `xcodegen` before the next build.

Hit this with the newly-bundled `places.geojson` — build was clean, runtime tripped the `guard let placesURL` fatalError. Fixed by regenerating + rebuilding.
