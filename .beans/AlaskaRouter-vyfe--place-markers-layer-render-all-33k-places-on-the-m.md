---
# AlaskaRouter-vyfe
title: Place-markers layer — render all 33k places on the map, zoom-tiered
status: in-progress
type: feature
priority: high
created_at: 2026-05-25T08:42:54Z
updated_at: 2026-05-25T16:47:08Z
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


## Iteration 2 — drop the dots, lower the zooms (2026-05-25)

User feedback after first on-device test:
1. *"More dots than names"* — labels collide-decimate; circles don't, so dots outnumber names visually.
2. *"At max zoom still had dots without names"* — same root cause; tile pack also caps at z=10 (see follow-up bean).
3. *"Love what I see, start showing earlier"* — lower minzoom on each tier.
4. *"Don't draw a dot on lakes"* — areal features (lakes/glaciers/parks/islands/volcano) are visually identifiable on the basemap; the dot was redundant.

### Changes

- **All 5 circle layers removed.** Only the label (symbol) layers remain — one per tier. Without the paired circles, the label IS the affordance and decimation is symmetric: a label shows up or doesn't, with nothing else hanging around it.
- **Lower minzooms** across all tiers:
  - `settlement_major` 6 → 4
  - `settlement / airfield / vc / ranger` 8 → 6
  - `natural-major (peak/glacier/park/fuel @ imp≥0.6)` 10 → 7
  - `misc (lake/viewpoint/attraction/marina + island/volcano/waterfall)` 12/13 → 9
  - `long-tail (everything else)` 14 → 11
- **`text-anchor` changed to `center`** so the label sits ON the lat/lon (no offset). For point features this puts the text right where the place is; for areal features the label drops near the centroid.
- **Per-category text-color** via `match` expression — peaks terracotta, glaciers slate blue, parks forest green, fuels red-orange, lakes deeper blue, etc. Cream halo (`rgba(255,250,238,0.92)`) for legibility on the warm OTM raster.
- **Volcano + waterfall + island** promoted from long-tail into misc tier (more deserving of an earlier appearance).

### Follow-ups noted

- Layer-toggle UI to disable categories — new bean.
- Higher-zoom tile pack (z=11+) — new bean.


## Iteration 3 — small monochrome icons, paired with labels (2026-05-25)

User feedback after iteration 2:
> "I didn't mean to remove all the dots/circles. They should appear/disappear together with their labels. We need some dot to make user know where exactly to tap. The dots are not good enough, we need small icons. Small and monochromatic (like those black mini-triangles for mountain peaks). A color and a small geometrical form."

### Architecture change

Each tier collapses to **one symbol layer** (was: paired circle+label layers in iteration 1, label-only in iteration 2). The symbol layer carries both `icon-image` and `text-field`. MapLibre's defaults (`icon-optional: false`, `text-optional: false`) mean BOTH parts must place or the *whole symbol* drops → icon and label appear/disappear together by construction.

### Marker design — 4 geometric shapes

| Shape | Categories |
|---|---|
| **▲ triangle** | peak |
| **■ square** | settlement_major, settlement (with different colors) |
| **+ cross** | airfield |
| **● dot** | every other point category (fuel, food, lodging, visitor_center, ranger_station, viewpoint, attraction, marina, volcano, hut, spring, …) |
| **(no icon)** | areal: glacier, park, lake, island, waterfall — label-only, anchored at centroid |

Each rendered at 16×16 via CoreGraphics in `PlaceIcons.swift`. Color baked in per-category from a warm-paper palette (peaks dark terracotta, fuel red-orange, ranger green, marina deep blue, etc.). Icons registered into MapLibre's style at runtime via `style.setImage(_:forName:)` inside the `unsafeMapViewControllerModifier` hook (idempotent — guarded by `style.image(forName:) == nil`).

### Layer behavior

Style layer's `icon-image` is a `match` expression on `category`. For point categories it returns `"place-<category>"` (e.g. `"place-peak"`); for areal categories it returns `""` → no icon, only the label, anchored at center.

`text-anchor` and `text-offset` are also data-driven by category: areal labels are centered (sit on the centroid); point labels sit `top` with a small downward offset so they appear under the icon. Both decimate together via the layer's default optional flags.

### Files

- **(new)** `AlaskaRouter/Map/PlaceIcons.swift` — shape + color logic, CoreGraphics rendering, runtime icon registration list.
- `AlaskaRouter/Map/ExpeditionMapView.swift` — register place icons in the unsafe map hook, once per style.
- `AlaskaRouter/Resources/style-base.json` — all 5 tiers become combined icon+label symbol layers.


## Iteration 4 — A/B/C spike harness (2026-05-25)

User feedback after iteration 3:
> "Thick black marks look ugly on our artistic map with labels which look creative with their thin white borders. Smaller or lively colors, even transparent and pale. Cluttered and invaded."

Brainstormed: at the scale we render (~10k visible symbols max), MapLibre's GPU-atlased symbol pipeline handles icons and text glyphs identically — performance is NOT the bottleneck. The constraint is **aesthetic coherence with the labels** (thin cream halo, warm-paper feel).

Built a 3-variant A/B harness behind a TweaksStore picker so the user can iterate visually:

| Variant | Spec |
|---|---|
| 0 | **Filled** (iteration 3 baseline) — saturated colored shape at 16 px |
| 1 | **Outline + cream halo** — stroke-only shape on a wider cream halo path, matching the labels' visual treatment. Interior is transparent so the basemap shows through. |
| 2 | **Smaller + translucent** — 10 px inset + 0.6 alpha. Faded version of 0. |

### Files

- `TweaksStore.swift` — `placeMarkerStyle: Int` (default 1 = outline+halo, the candidate).
- `TweaksPanel.swift` — new "Place markers (vyfe spike)" section with inline picker.
- `PlaceIcons.swift` — `render` now dispatches on style: `renderFilled` / `renderOutlineHalo` / `renderTranslucent`. New `path(for:in:)` helper builds the geometry once; each variant strokes/fills/translates differently.
- `ExpeditionMapView.swift` — registration block tracks `PlaceIcons.lastRegisteredStyle`; on mismatch it removes + re-registers every category icon. Live switch — no app restart needed.
- `RootView.swift` — `tweaksFingerprint` extended with `placeMarkerStyle` so the map view re-renders (and the unsafe hook re-fires) on picker change.

### How to use the spike

Open the wrench panel (top-left), scroll to **Place markers (vyfe spike)**, flip the picker between 0/1/2, close the panel. The next pan/zoom triggers a hook fire and the icons swap live.

Pick the winner and let me know — I'll delete the other two variants + the picker, and lock the style.


## Iteration 5 — SF Symbol glyphs per category, 4 variants (2026-05-25)

User feedback after iteration 4:
> "I loved the aircraft glyph you used above, why won't we draw it like that on the map instead of a cross? Let's draw corresponding glyphs for everything they exist for. Settlement → house. Airfield → aircraft. Fuel → canister. Ranger station → uniformed head or human figure. Volcano → volcano. Viewpoint → eye."
> "The circle shape should be bigger I hardly can see it."
> "If we cannot have them as outline, let's fallback on translucent — maybe tweakable halo around them."

### Approach pivot

Dropped the 4-shape geometric set entirely. Each point category now maps to a category-specific **SF Symbol** baked into a 22×22 bitmap (was 16×16 — bumped per user's visibility complaint). Apple's symbol library covers everything we need:

| Category | SF Symbol |
|---|---|
| settlement_major | `building.2.fill` |
| settlement, locality, hut | `house.fill` |
| airfield | `airplane` |
| marina | `ferry.fill` |
| fuel | `fuelpump.fill` |
| ev_charging | `bolt.fill` |
| vehicle_service | `wrench.fill` |
| food, picnic | `fork.knife` |
| lodging | `bed.double.fill` |
| camping | `tent.fill` |
| visitor_center | `info.circle.fill` |
| ranger_station | `shield.lefthalf.filled` |
| post, bank | envelope / creditcard |
| medical | `cross.case.fill` |
| pharmacy | `pills.fill` |
| store, outdoor_shop, hardware | cart / mountain.2 / hammer |
| viewpoint | `binoculars.fill` |
| attraction | `star.fill` |
| historic | `building.columns.fill` |
| lighthouse | `lightbulb.fill` |
| peak | `triangle.fill` |
| volcano | `flame.fill` |
| spring, water | `drop.fill` |
| tower | `antenna.radiowaves.left.and.right` |
| river_crossing | `water.waves` |
| parking | `parkingsign.circle.fill` |

Each symbol has both a filled (`house.fill`) and outline (`house`) variant; the renderer picks based on the chosen visual variant.

### 4 visual variants (live A/B picker)

| Tweak | What |
|---|---|
| 0 — Filled (baseline) | saturated colored SF Symbol, no halo |
| 1 — Outline + cream halo *(default)* | outline SF Symbol in category color + cream halo via `CGContext.setShadow(blur:1.8, color: cream)` |
| 2 — Translucent (no halo) | filled SF Symbol at 0.65 alpha |
| 3 — Translucent + cream halo | filled SF Symbol at 0.65 alpha + cream halo |

The halo is implemented via `CGContext.setShadow(offset: .zero, blur: 1.8, color: cream)` before drawing the tinted symbol. Soft cream rim around every glyph-edge pixel — matches the labels' cream halo aesthetic.

### Files

- `PlaceIcons.swift` — rewritten. New `sfSymbol(for:)` mapping; new `renderGlyph(category:color:outline:withHalo:)` drawing path. 22-px canvas, 14-pt symbol point size, semibold weight for outline / regular for filled.
- `TweaksPanel.swift` — picker bumped to 4 options.

### Implementation notes for future work

- SF Symbol bitmaps tint cleanly via `image.withTintColor(color, renderingMode: .alwaysOriginal)`.
- `CGContext.setShadow` is the simplest way to halo arbitrary alpha-shaped imagery — works for both outline AND filled symbols.
- Areal categories (`glacier`, `park`, `lake`, `island`, `waterfall`) still return nil from `image(for:)` and remain label-only.


## Iteration 6 — visible halo + bigger glyphs (2026-05-25)

User feedback after iteration 5:
> Translucent works better. "Talking" icons — significant positive impact.
> - I don't see halo for any of the options. I definitely would like to see halo.
> - Binoculars are too small.
> - Ferry points (labels say "Ferry") are shown as "house". Is it something we could fix?

### Halo — root cause + fix

The `CGContext.setShadow(blur:color:)` approach from iteration 5 didn't work because:
1. `UIImage.draw(in:)` rasterizes the symbol THROUGH the shadow context, but the shadow state doesn't always propagate cleanly to rasterized images (CGImage compositing).
2. Even when shadow renders, a 1.8-px cream blur is nearly invisible against the warm OpenTopoMap basemap (cream-on-cream).

Replaced with **8-direction morphological dilation**: render the cream-tinted SF Symbol 8 times offset by ±2 px (and 8 more at ±1 px to fill gaps), then the category-colored symbol on top. The cream offsets accumulate into a sharp ~2-px rim around the glyph silhouette. Reads cleanly against any background, including warm-paper terrain.

Cost: 16 cream `draw(in:)` calls + 1 colored draw = 17 raster passes per icon. ~30 categories registered → ~510 draws on style change. Sub-millisecond on iPhone 16.

### Bigger glyphs

- Canvas 22 → **26 px** (gives room for the 2-px halo without clipping)
- Symbol point size 14 → **17 pt**

Triangle.fill / airplane / fuelpump.fill stay clearly readable; binoculars (now `eye.fill` per user's "Egyptian eye" suggestion) and other intricate glyphs gain enough pixels to be recognizable.

### Viewpoint glyph

Changed `viewpoint` from `binoculars.fill` → **`eye.fill`** per user suggestion. The eye is a simpler silhouette that reads better at small size. Binoculars has too much internal detail.

### Ferry "house" mystery — explained, NOT a bug

Investigated:
```
SELECT name, category FROM place_meta WHERE name LIKE '%ferry%';
```

- ~25 entries with "Ferry" in name are categorized as `marina` (ferry icon, correct).
- 2 entries named **just "Ferry"** are categorized as `settlement` (house icon, ALSO correct). These are an actual unincorporated community — *Ferry, Alaska* — in Denali Borough, pop. ~35, OSM-tagged `place=hamlet`. The name happens to be "Ferry" but it's a real village.
- A few "Ferry loading lanes" / "Ferry Terminal Parking" are `parking` (parking icon, correct).

So nothing to fix in the data; the house icon on "Ferry, AK" is geographically accurate. Ferry TERMINALS appear at z=9+ (misc tier) with the ferry icon as expected; below z=9 only settlement-tier features show, including the village.

### Files

- `PlaceIcons.swift` — `renderGlyph` uses 8+8 cream-offset dilation when `withHalo`; canvas and point-size constants bumped; `viewpoint` symbol mapped to `eye.fill`.


## Iteration 7 — winner locked + peak size + label-size slider (2026-05-25)

User feedback:
> "Number 3, Translucent+cream halo EASY WIN. Eye icon is gorgeous, it's almost winking."
> "Peak icon can be a bit smaller — too many of them, they clutter."
> "POI label font size is small — want it tweakable, may want to follow iOS pref later."
> "What is the big-building icon at low zoom at Allakaket, Bettles, Anaktuvuk Pass, Delta Junction that disappears on zoom-in?"

### Winner locked

Default `placeMarkerStyle` flipped to **3** (translucent + cream halo). The 0/1/2 variants stay in the picker for future iteration; harness will be retired once we're done iterating.

### Peak size — style match expression

Peaks were drawing at the same icon-size as fuel, glaciers, parks. Triangles are recognizable even when small, and there are thousands of them, so they clutter the view at z=10+. Now peaks scale 0.45→0.65 across z=7→z=13 (was 0.7→1.0). Fuel and other natural-major categories keep the original size.

### Label-size multiplier

New TweaksStore knob `labelSizeMultiplier: Double` (default 1.0, range 0.70–1.50, step 0.05). New file `MapLabelSizing.swift` mirrors the text-size stop schedule from style-base.json (9 layers: 4 curated anchor labels + 5 places-tier-* layers) and rebuilds each layer's `textFontSize` NSExpression with every stop value scaled. Applied from the unsafe map-view modifier hook; idempotent guard on `lastAppliedMultiplier`. Future work: drive from iOS Dynamic Type as an additional input.

### "Big building" at low zoom — explained, NOT a bug

User reported a building-like icon at Allakaket, Bettles, Anaktuvuk Pass, Delta Junction that disappears on zoom-in. Investigation: those are **OpenTopoMap's baked-in raster labels** — OTM's tile renderer paints a small icon + name at population centers. At z=4-5 only the raster is visible; at z=6+ our vector overlay starts drawing on top and visually "replaces" them.

True fix is `6ihk` (self-render OpenTopoMap). Until then, the z=5↔6 transition is the raster-vs-vector handoff. Not a vyfe issue.

### Files

- `TweaksStore.swift` — added `labelSizeMultiplier`; default `placeMarkerStyle` flipped 1→3.
- `TweaksPanel.swift` — slider for label size; picker badge "✓" on variant 3.
- `style-base.json` — peak `icon-size` match expression (peaks smaller than glaciers/parks/fuel).
- `MapLabelSizing.swift` — new. Mirror of label text-size schedules; applies multiplier at runtime.
- `ExpeditionMapView.swift` — call `MapLabelSizing.apply` in the unsafe hook.
- `RootView.swift` — added `labelSizeMultiplier` to `tweaksFingerprint`.


## Iteration 8 — peak regression fix + settlement circle (2026-05-25)

User feedback after iteration 7:
> "I don't see peaks at all including their labels. Regression?"
> "Settlement icon (house) is a bit cluttering, let's switch to a small empty circle with halo — sized like a small 'o'. Other icons are good."

### Peak regression

Suspected: the iteration-7 `match` expression on `icon-size` in `places-tier-natural-major` (peak: 0.45-0.65, others: 0.7-1.0) silently broke MapLibre's parsing for the whole layer. MapLibre style errors can be silent — a malformed nested-interpolate-inside-match expression often just drops the layer with no visible diagnostic.

**Fix:** split peaks into their OWN layer `places-tier-peak`. Simple, no nested expressions, the icon-size is a flat interpolate (0.45→0.65). `places-tier-natural-major` now carries glacier/park/fuel only.

This also removes any temptation to use `match` expressions on icon-size in the future — splitting layers is cleaner.

### Settlement → small open circle

PlaceIcons SF Symbol mapping for `settlement`, `locality`, `hut` changed from `house.fill`/`house` → `circle`/`circle` (outline glyph in BOTH the filled and outline slots — produces a hollow ring in every visual variant).

Plus a new `pointSize(for:)` per-category override: settlement/locality/hut get glyph point size **11** (was the global 17). Reads as a small "o" — paper-atlas village convention. Other categories keep 17.

Combined with the variant-3 cream halo, settlements now render as a small hollow circle wrapped in cream. The visual user explicitly asked for.

### Files

- `style-base.json` — new `places-tier-peak` layer (peaks only, small icon, flat interpolate); `places-tier-natural-major` now filters to `glacier`/`park`/`fuel`.
- `MapLabelSizing.swift` — added `places-tier-peak` to the text-size schedule so the user's label-size multiplier applies to peak labels too.
- `PlaceIcons.swift` — settlement/locality/hut now use SF `circle` (outline) in both variant slots. New `pointSize(for:)` override.
