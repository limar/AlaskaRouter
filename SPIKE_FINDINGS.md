# Spike findings

Three de-risking spikes ran before scaffolding the real `AlaskaRouter` app. All three are green; this document persists the learnings, decisions, and remaining open questions so they survive across sessions.

- [Spike A — Map rendering & annotation](#spike-a--map-rendering--annotation)
- [Spike B — Places search (FTS5)](#spike-b--places-search-fts5)
- [Spike C — Expedition style (cartography)](#spike-c--expedition-style-cartography)
- [MapLibre Native iOS gotchas (4)](#maplibre-native-ios-gotchas-4)
- [Carry-forward into the real app](#carry-forward-into-the-real-app)
- [How to rerun the spikes](#how-to-rerun-the-spikes)

## Headline (locked 2026-05-18)

After three rounds of style iteration and a ten-way basemap evaluation, the v1 map plan is locked:

- **Basemap: OpenTopoMap, raster, bundled offline as PMTiles** per region. The visual stunned the user where every other vector-based attempt fell flat. `denali-otm.pmtiles` (12 MB, z=4–10, Denali / Parks Highway region) is in the repo as the proof-of-concept pack.
- **Trip overlay: MapLibre vector layers** on top of the raster (LineLayer for the route, SymbolLayer for waypoint markers + labels). Stays glued through pan/zoom/pitch/rotate, validated by the spike.
- **Routing: online via OSRM/ORS** at plan time → `SegmentGeometry.snapped(polyline, computedAt)`. Cached in SwiftData.
- **Offline-at-plan-time fallback (rare)**: Catmull-Rom spline through waypoints, marked `pendingSnap: true`. Auto-upgraded to the real road geometry when network returns (Apple's `NWPathMonitor`).
- **Real offline routing**: explicitly deferred to v2+. Bundling Valhalla or equivalent is real engineering and not v1-feasible.

## TL;DR — what the spikes confirmed

1. **MapLibre Native iOS 6.26.0 + `swiftui-dsl` builds clean on Xcode 26.5 / iOS 26.5 / Swift 6** and renders smoothly with custom `ShapeSource`s and declarative `SymbolStyleLayer` / `LineStyleLayer` modifiers.
2. **`pmtiles://` URLs work out of the box** in the prebuilt distribution — no protocol handler code needed, range-requested HTTP, both remote and local files (`file://`) accepted.
3. **AWS Terrarium DEM tiles** are a free, key-less hillshade source that gives the map the topographic depth the brief calls for. Mapterhorn PMTiles is a viable alternative (705 GB, range-requested).
4. **SQLite FTS5 + a two-stage retrieval (strict prefix-AND → relaxed prefix-OR + edit-distance rerank) + a soft category-facet boost** answers 12/12 of a real expedition query battery on the Alaska dataset (12,617 deduped POIs, 3.1 MB).
5. **Per-keystroke search auto-suggestions are feasible in v1**: stage 1 queries return in ~1–3 ms on the 12k-row Alaska DB. A 150 ms debounce on input is comfortable.
6. **OpenFreeMap is a viable online basemap source** with no API key needed; OpenMapTiles schema, free for project-scale use. Pairs well with our `pmtiles://` future for offline.

---

## Spike A — Map rendering & annotation

Code: [spikes/A_maplibre/](spikes/A_maplibre/) — generated Xcode project from [project.yml](spikes/A_maplibre/project.yml).

### What we proved

1. **MapLibre Native iOS builds and renders on iOS 26.5 sim from `iPhone 17 Pro`.** Build is reproducible from a checked-in `project.yml` + `xcodegen generate`.
2. **`MapLibreSwiftUI`'s declarative DSL** ([`MapView`](spikes/A_maplibre/build/SourcePackages/checkouts/swiftui-dsl/Sources/MapLibreSwiftUI/MapView.swift), `ShapeSource`, `SymbolStyleLayer`, `LineStyleLayer`) is good enough for our needs. We don't need to drop to `UIViewRepresentable` for the v1 annotation/route work.
3. **Annotations stay glued to a geographic coordinate** across pan, zoom (z=5.5 to z=11.5 verified), pitch (45°), and bearing (30°). The MapLibre projection handles this for us automatically when annotations live in a `ShapeSource`.

### v1 of the spike (initial validation)

- Style: OpenFreeMap "liberty" via `https://tiles.openfreemap.org/styles/liberty`.
- Annotation: one SwiftUI-style label + line layer over a `ShapeSource` of `(point + linestring)` at Denali.
- 5 screenshots across `(zoom × pitch × bearing)` confirmed glue behaviour.

### Spike A.5 — PMTiles validation

We swapped the styleURL to a bundled `style-pmtiles.json` whose vector source uses:

```json
"sources": {
  "nz_buildings": {
    "type": "vector",
    "url": "pmtiles://https://r2-public.protomaps.com/protomaps-sample-datasets/nz-buildings-v3.pmtiles"
  }
}
```

**Result**: builds and renders without any extra code or dependency. MapLibre Native intercepts the `pmtiles://` scheme internally, makes HTTP range requests, and parses the PMTiles directory. The prebuilt distribution (`maplibre-gl-native-distribution` 6.26.0) **does** have `MLN_WITH_PMTILES` enabled.

Confirmed by inspecting the iOS CHANGELOG: PMTiles support landed in [PR #2882](https://github.com/maplibre/maplibre-native/pull/2882) and has been refined since ([#3403](https://github.com/maplibre/maplibre-native/pull/3403), [#4159](https://github.com/maplibre/maplibre-native/pull/4159)).

**Sample-URL caveat**: the originally-cited `protomaps-basemap-opensource-20230408.pmtiles` URL returns 404 in 2026; Protomaps moved sample data. Currently-working public URLs:

- `https://r2-public.protomaps.com/protomaps-sample-datasets/nz-buildings-v3.pmtiles` (289 MB, NZ building footprints)
- `https://download.mapterhorn.com/planet.pmtiles` (705 GB, planet terrain, terrarium-encoded)
- `https://r2-public.protomaps.com/protomaps-sample-datasets/terrarium_z9.pmtiles` (30 GB, terrain)

For the real app, **we generate our own PMTiles per region** via `tilemaker` or `planetiler` (Tools/build-pack/). Public sample URLs are fragile.

---

## Spike B — Places search (FTS5)

Code: [spikes/B_fts5/](spikes/B_fts5/) — build pipeline in [build/](spikes/B_fts5/build/), Swift test in [swift/](spikes/B_fts5/swift/).

### Pipeline

1. `osmium tags-filter` → [data/alaska-filtered.osm.pbf](spikes/B_fts5/data/) (only expedition-relevant tags)
2. `osmium export --add-unique-id=type_id -f geojson` → GeoJSON
3. Python ([build_fts5.py](spikes/B_fts5/build/build_fts5.py)) builds:
   - `place_meta(osm_type, osm_id, lat, lon, category, importance, name, alt_names)`
   - `places_word` FTS5 with `unicode61 remove_diacritics 2`, `prefix='2 3 4 5'`
   - `metadata` (schema_version, built_at, source_md5, places_inserted, places_collapsed)

### Numbers on the Alaska dataset

- 59,438 raw OSM features after tag-filter
- 16,580 categorized + named (29,710 unnamed dropped, 13,221 in tag-filter slop)
- **12,617 deduped** (collapsed 3,963 = 24% duplicates on `(name_casefold, lat_rounded_3dp, lon_rounded_3dp)`)
- **3.1 MB** SQLite (half the size of the v1 build, which still had a useless trigram table)

### Query subsystem (Swift test in [main.swift](spikes/B_fts5/swift/Sources/QueryTest/main.swift))

Two-stage retrieval:

1. **`CategoryFacetParser`**: greedy multi-word phrase match against a list mapping surface forms ("visitor center", "ranger", "fuel", "hot spring", …) to canonical categories. Strips them from the query; the rest are name tokens.
2. **Stage 1** (strict): `name_token1* name_token2* …` FTS5 prefix-AND on the name tokens, with category hints applied as a **soft boost in the score expression** (`-3.0` when a row's category matches), not a hard `WHERE` filter. Important: if we hard-filter and the data lacks rows in that category, we get zero hits even when good name matches exist.
3. **Stage 2** (fallback when stage 1 returns nothing): relaxed prefix-OR using the first 3 chars of each name token, then in-Swift Levenshtein rerank against `name + alt_names`. Categorical boost is also applied here.

### Quality result (12/12 on the test battery)

| Case | Query | Stage | Pass |
|---|---|---|---|
| exact two-word | "Wrangell visitor center" | s1 | ✓ |
| place + feature | "Tok junction" | s1 | ✓ |
| famous pass | "Atigun pass" | s1 | ✓ |
| place + category | "Coldfoot fuel" | s1 | ✓ |
| single word | "Denali" | s1 | ✓ |
| city name | "Anchorage" | s1 | ✓ |
| city + category (no exact match in data) | "Fairbanks ranger" | s1 | ✓ |
| typo of Wrangell | "Wrangle visitor center" | **s2** | ✓ |
| typo of Atigun | "Atagun pas" | **s2** | ✓ |
| alternate spelling | "Glaciar bay" | s1 | ✓ |
| Dalton highway (partial) | "Dalton" | s1 | ✓ |
| place + category (no exact match) | "Chena hot spring" | s1 | ✓ |

### Key learnings

- **The trigram FTS5 tokenizer adds no recall over `unicode61 + prefix`** on real typos: e.g. trigrams of `wrangle` (`wra, ran, ang, ngl, gle`) and `wrangell` (`wra, ran, ang, nge, gel, ell`) only share 3/5. Edit-distance rerank handles the same cases more reliably and lets us drop the trigram index entirely (saves ~3 MB).
- **Dedupe on the build side** (collapsing OSM duplicates) is non-negotiable. 24% of rows were duplicates here.
- **Glob `name:*` and `alt_*` keys** instead of a curated list. We didn't need it for the test battery, but it's the only way to cover Alaska indigenous names (Athabaskan, Iñupiaq, Yup'ik).
- **Category hints are soft, not hard.** "Fairbanks ranger" has zero `category=ranger_station` rows with `fairbanks` in the name — soft boost still surfaces "Fairbanks Convention & Visitors Bureau" etc., hard filter returns nothing.
- **Per-keystroke search is fine** at the data scale: stage 1 typically completes in 1–3 ms.

### Bind-parameter ordering bug (worth a v1 unit test)

The SQL bind positions must match the **textual** order of `?` placeholders. Our stage 1 SQL puts the category-hint placeholder inside the `SELECT` `CASE`-expression (textually before the `WHERE` clause), so it has to be bound first. Initial code bound FTS match first, scrambling the parameters — got plausible-looking but wrong results. **The real app's search needs a test that asserts a query for "X Y" returns rows containing X or Y.**

---

## Spike C — Expedition style (cartography)

Style: [Resources/style-expedition.json](spikes/A_maplibre/Resources/style-expedition.json) — loaded by the same iOS spike.

### v1 (deferred — pale and low-contrast)

Initial palette was correctly muted but missing terrain — large stretches of Alaska looked blind. Direct user feedback: "pale low contrast etc, zoom out show empty/blind map."

### v2 (current — terrain-driven)

Adds, vs. v1:

- **`raster-dem` source** from `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` (free, public, terrarium-encoded).
- **`hillshade` layer** with warm shadows (`#7a5a30`), cream highlights, illumination from 315°.
- **Vibrant roads with cream casings**: trunk `#5e3aa8`, primary `#7b58c4`, secondary `#c89a5c`. The casing pattern is what gives the printed-atlas character.
- **Letterpress region names** (`place=state/province`) — uppercase, 0.45 letter-spacing, faded brown, opacity tapered with zoom.
- **Italic water labels** along rivers via `symbol-placement: line`.
- **Brighter glaciers** with `#f4f7f8` fill + soft outline.

### Verified visually (screenshots at z=3.5 / z=4.5 / z=6.5 / z=9 pitched)

- "ALASKA" rendered in faded letterpress at z=4.5+.
- Brooks Range, Alaska Range visible as terrain ridges.
- Glacier fields rendered as white masses.
- Anchorage / Fairbanks / Kodiak labeled at z=4.5.
- 3D pitched view at z=9 shows named peaks (Mt Hunter, Mt Crosson, Kahiltna Peaks, Denali).

### v3 — taiga + tundra (the "where are my forests" iteration)

The v2 map was correct for the Alaska Range (glaciers + relief) but looked all tundra at planning zooms because OpenFreeMap's `landcover` layer carries **only glaciers** for Alaska — at z=5 an interior-Alaska tile contains 49 features, all `class=ice`, zero `wood/forest/grass/wetland`. Confirmed by decoding a tile with `mapbox_vector_tile`: `landcover: 49 feats, classes={'ice': 49}`. Same at z=8.

**Workaround used in v3:** paint the **`park`** layer as graded greens. The park layer carries 136 features at z=5 for Alaska including 4 National Forests (Tongass, Chugach, ...), 21 Wilderness Areas, 21 Nature Reserves, 45 National Parks, 9 Protected Areas, 7 National Preserves, etc. These are an excellent proxy for "forested wilderness" in Alaska. Classes mapped to greens:

| Park class                  | Fill         | Use case |
|-----------------------------|--------------|----------|
| `national_forest`, `state_forest` | `#5a9047` | richest green — actual forest land |
| `wilderness_area`, `nature_reserve`, `national_wildlife_refuge` | `#6ba551` | strong green — protected wilderness |
| `national_park`, `national_preserve`, `national_monument` | `#83b86b` | medium green — mixed terrain |
| `state_park`, `state_recreation_area`, `protected_area` | `#9bc77f` | lighter green |
| `wildlife_sanctuary`, `state_game_refuge`, `state_moose_range` | `#b5cd83` | tan-green |

**Hillshade layered last (just before roads)** at low alpha (`rgba(78, 50, 18, 0.32)` shadow), so parks render fresh underneath and hillshade only ghosts depth on top.

### Open data-source question — needs a v1 decision

OpenFreeMap's missing landcover data is a real gap for our use case. Three paths forward; **decide before scaffolding the real `Map/` module**:

1. **Stay on OpenFreeMap + parks-as-forests proxy** (current v3). Works visually at z=4+, breaks at z<4 (no parks served), and doesn't surface OSM-tagged forests outside parks (which exist in Alaska — Tetlin Hills, Brooks Range slope, etc).
2. **Switch to MapTiler Outdoor** (keyed/paid). Has real `landcover_class=wood/grass/farmland` at all zooms. Best visual fit; reintroduces a key dependency.
3. **Generate our own PMTiles** via `tilemaker` or `planetiler` from OSM extracts (the same `Tools/build-pack/` pipeline). Full control — we can keep forest features at any zoom we want. Slowest start, best long-term fit, fully open-source.

### Still missing vs. the mockup (real-app polish, not spike work)

1. **Paper-grain background pattern** — needs a sprite-sheet PNG + `background-pattern: "grain"`.
2. **Stippled-dot forest pattern** — `fill-pattern` referencing a small repeating tile image.
3. **Hand-drawn circle-bullet place markers** — `◎`/`⊙` glyphs in front of city/town labels, or custom SDF icons.
4. **Vibrant road visibility at z<4** — currently filtered out; relax to include primary at lower zooms when planning continent-scale views.
5. **Statewide-zoom (z<4) greenery** — needs either landcover fix above or a low-zoom land-tint overlay.

These are all `fill-pattern` / `background-pattern` work that needs a sprite-sheet asset pipeline — out of scope for a style-tuning spike, in scope for the real `AlaskaRouter/Map/` module.

---

## Spike C — version 3.1: parks-as-forests failure

Attempt: paint the OFM `park` source-layer with graded greens (national_forest, wilderness_area, national_park, state_park, wildlife_sanctuary) to give Alaska some visible vegetation despite OFM's missing landcover data.

User verdict (verbatim): *"The mountain ranges are water-blue now! Some yellow color I don't know what it should mean. Everything is vibrant but colored just randomly."*

The fundamental problem: park polygons are **administrative**, not ecological. National parks cover everything from sea level forests to alpine glaciers — painting them green created obvious visual lies (green over peaks above the tree line). **Approach dead. Don't revisit.**

## Spike WorldCover overlay — Path 4, also failed

Attempt: bundle a low-resolution ESA WorldCover 2021 raster (real ecological land-cover data) as an `image` source overlay under our vector style. 4864×2048 PNG, ~920 KB, covering Alaska bounds via 152 WMTS tiles stitched with ImageMagick.

What worked:
- Data is correct. Forests appear in the right places (interior taiga), glaciers in the Alaska Range, water in Cook Inlet.
- The PNG-overlay approach renders at all zooms via MapLibre's `image` source.
- Fully offline (PNG bundled in the app).

What failed:
- **Pixelated above z=7** — our mosaic was only z=6 resolution, so glaciers at z=9 turn into blue Minecraft blobs.
- **Garish raw ESA palette** — designed for scientific use, not aesthetic. Even with `raster-saturation: 0.1` and tonal tweaks it reads as a satellite indicator, not a map. User: *"This is terrible. Worst result till now."*

A higher-resolution PMTiles pyramid (z=0–9 ESA WorldCover ≈ 50–100 MB) would fix the pixelation but not the aesthetic. The fundamental issue is that a categorical raster painted on top of vector layers will never feel like an atlas. **Approach dead. Files retained (`Resources/style-worldcover.json`, `Resources/worldcover-alaska.png`) for archival evidence only.**

## Ten-way basemap evaluation

Rendered all of these at identical camera positions over central Alaska (z=3.5 statewide, z=6.5 mid, z=9 alpine, z=9 pitched, z=4.5 wide). User-graded:

| Candidate | Type | Verdict |
|---|---|---|
| **OpenTopoMap** | Free raster, no key | **"Something from another world. Makes me love my planet."** — winner |
| MapTiler Topo | Premium vector (key) | "Not bad. Usable." |
| Thunderforest Outdoors | Premium raster (key) | "So-so or even ok." |
| Thunderforest Landscape | Premium raster (key) | "So-so or less." |
| MapTiler Landscape | Premium vector (key) | "So-so." |
| MapTiler Outdoor | Premium vector (key) | "Sucks." |
| Thunderforest Atlas | Premium raster (key) | "Sucks." |
| Thunderforest Pioneer | Premium raster (key) | "Sucks (looks exactly as Atlas)." |
| CyclOSM | Free raster, no key | "Just bad." |
| Our v3.1 (hand-tuned vector) | OFM vector + hand style | "Coloring incorrect. Useless." |

Comparison contact sheets persisted at `/tmp/spike-shots/comparison-{z3.5,z6.5,z9}-*.jpg` and per-style screenshots at `/tmp/spike-shots/cmp/<style>/t{1..5}.png` (gitignored, regenerable from `/tmp/compare-basemaps.sh`).

## Spike: OpenTopoMap PMTiles offline + vector overlay (the locked v1 architecture)

Built the full vertical slice: bundled offline OpenTopoMap raster basemap loaded from a PMTiles file, with a real snap-to-road route + waypoint markers + labels rendered as MapLibre vector layers on top.

**Pipeline (reproducible):**

1. `python3 /tmp/dl-otm-denali.py` — polite, rate-limited (0.4s) download of OpenTopoMap raster tiles for the Denali / Parks Highway region (lat 62.5–65, lon -152 to -147, zooms 4–10). 367 tiles, 13.3 MB, ~6.5 min single-threaded. Written directly into an MBTiles SQLite file with proper metadata + TMS row ordering. User-Agent identifies the requestor; well within their personal-use politeness limits.
2. `pmtiles convert /tmp/denali-otm.mbtiles /tmp/denali-otm.pmtiles` — single-file archive, 12 MB. Bundled into `Resources/denali-otm.pmtiles`.
3. `curl https://router.project-osrm.org/route/v1/driving/...?overview=full&geometries=geojson` — fetch real road geometry between 5 Parks Highway waypoints (Cantwell → Denali Park Entrance → Healy → Nenana → Fairbanks). 260 km, 3233 polyline points. Saved as `Resources/demo-route.geojson` (82 KB).
4. MapLibre style (`Resources/style-opentopomap-offline.json`) references the bundled PMTiles via `pmtiles://file://…` URL (works because MapLibre Native iOS 6.26.0 has native PMTiles support — see Spike A.5).
5. ContentView (`Sources/ContentView.swift`) adds the route + waypoint markers as MapLibre vector layers on top, conditional on the active style being `style-opentopomap-offline`.

**What this proves:**
- v1 map architecture is end-to-end: OpenTopoMap basemap offline + MapLibre vector overlay for trip planning, all rendering correctly through pan/zoom/pitch/rotate.
- The bundle-format decision (PMTiles) is right: single 12 MB file, MapLibre reads natively, MBTiles → PMTiles conversion takes <1 second.
- The "manual bundle delivery" simplification is right for v1: no downloader UI, no progress bars, no network state — just place the file in iCloud Drive / Documents / app bundle.

**Known polish items (NOT architectural):**
- Custom marker icons (SF Symbol inside cream disc) render only the cream disc + red mappin — my UIImage composition needs a fix.
- Glyphs are still fetched online from `tiles.openfreemap.org/fonts/...`. For fully-offline labels: bundle a Noto Sans glyph fontstack (~50 PBF files, ~50 KB).
- DSL's `iconImage(featurePropertyNamed:mappings:default:)` does not work in our package configuration (their own demo of it is commented out as "doesn't work within package"). We use a single icon for all markers as a workaround. Per-type icons need either custom NSExpression construction or a different DSL pattern.

## Decision: routing strategy across versions (locked 2026-05-18)

See [memory: project_routing_strategy.md](/Users/mlifshits/.claude/projects/-Users-mlifshits-work-AlaskaRouter/memory/project_routing_strategy.md).

- **v1**: online routing via OSRM/ORS at plan time → cached `SegmentGeometry.snapped` in SwiftData. Offline-at-plan fallback: Catmull-Rom spline through waypoints, marked `pendingSnap: true`, auto-refreshed on reconnection via `NWPathMonitor`.
- **v1 or v1.5**: visual `pendingSnap` indicator — dashed line + small wifi-slash icon + tap-to-explain sheet.
- **v2+**: real offline routing engine (Valhalla likely), bundled per region alongside PMTiles + FTS5.

## Data model extension to bake in v1

```swift
enum TravelMode: String, Codable {
  case road, flight, ferry, walking
}

enum SegmentGeometry: Codable {
  case straight                                          // simple geodesic line
  case spline                                            // Catmull-Rom curve through waypoints
  case snapped(encodedPolyline: String, computedAt: Date)
}

@Model final class RouteSegment {
  // existing fields …
  var mode: TravelMode
  var geometry: SegmentGeometry
  var pendingSnap: Bool          // true when drawn offline, awaiting reconnection refresh
}
```

---

## MapLibre Native iOS gotchas (4)

Real things we tripped on; these belong in the real app's `Map/` module as design constraints.

1. **The `$type` NSPredicate variable is not supported.** `NSPredicate(format: "$type == 'LineString'")` throws `NSInvalidArgumentException` at style-load time. Use separate `ShapeSource`s per geometry type, or filter by an explicit feature attribute we set ourselves.
2. **The DSL's `textAnchor` (and `iconAnchor`, `symbolPlacement`, etc.) takes a `String`, not an enum.** The macro generates `@MLNStyleProperty<String>`. Wrap in our own typed enum at the call site (`enum TextAnchor: String { case bottom = "bottom" }`).
3. **`SymbolStyleLayer` silently renders nothing without `textFontNames`** matching a font available at the style's `glyphs` endpoint. Set the project default centrally and fail loudly if missing.
4. **Macro trust is required for the SwiftPM-based MapLibreSwiftUI build.** First-time CLI builds fail with `"Macro ... must be enabled before it can be used"`. Fix:

   ```sh
   defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
   defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
   ```

   And pass `-skipMacroValidation -skipPackagePluginValidation` to `xcodebuild`. This needs to be in any CI script we write.

---

## Carry-forward into the real app (updated 2026-05-18 after map locking)

In rough priority order:

1. **`Tools/build-pack/`** — port [build_fts5.py](spikes/B_fts5/build/build_fts5.py) and `/tmp/dl-otm-denali.py` as the two pipelines that produce regional packs. Outputs: `<region>.pmtiles` (OpenTopoMap raster), `<region>-places.sqlite` (FTS5 search), `<region>-route-cache.geojson` (optional cached routes), `manifest.json`.
2. **`AlaskaRouter/Map/`** — three responsibilities:
   - **Basemap loader**: MapLibre + the bundled `<region>.pmtiles` via `pmtiles://file://…` URL.
   - **Vector overlay**: route LineLayer + waypoint SymbolLayer + (v2) annotations LineLayer, all reading from GeoJSON ShapeSources kept in sync with SwiftData.
   - **Bundled glyphs**: ~50 KB of Noto Sans PBFs in `Resources/glyphs/` for fully-offline label rendering.
   - **The four MapLibre gotchas** (the `$type` NSPredicate ban, String-typed anchor enums, required `textFontNames`, macro-trust CI flag) baked in as constants/helpers.
   - Note: hand-tuned vector style (the failed Spike C track) is **abandoned**. Don't carry it forward.
3. **`AlaskaRouter/Routing/`** — see [memory: project_routing_strategy.md](/Users/mlifshits/.claude/projects/-Users-mlifshits-work-AlaskaRouter/memory/project_routing_strategy.md).
   - `RoutingProvider` protocol; concrete `OpenRouteServiceProvider` (user key) + `OSRMPublicProvider` (key-free fallback) + `GeodesicFallbackProvider` + `SplineFallbackProvider` (Catmull-Rom).
   - `NWPathMonitor` watching network state; on reconnection, fire routing for all `pendingSnap` segments.
   - `RouteSegment.geometry: SegmentGeometry` enum (`.straight | .spline | .snapped(polyline, computedAt)`).
   - `RouteSegment.pendingSnap: Bool`.
4. **`AlaskaRouter/Search/`** — port the [Swift query layer](spikes/B_fts5/swift/Sources/QueryTest/main.swift). Add: per-keystroke debounce (~150 ms), in-viewport spatial boost (add `distance(lat,lon,viewport_center)` to the score), search-result dedupe on display.
5. **`AlaskaRouter/Bundles/`** — discovery + manifest parsing + iCloud Drive / Files import of `<region>.expack` folders containing PMTiles + glyphs + places SQLite.
6. **Bind-parameter unit test** for the search SQL — see B.5 bug above. Cheap, high-value.
7. **TravelMode + SegmentGeometry data model** baked into SwiftData from day one (see "Data model extension" above), even though v1 only exercises `.road` / `.spline`.

**Deferred to later versions:**
- v1.5: `pendingSnap` visual indicator (dashed line + wifi-slash icon + explanation sheet).
- v2: real offline routing (Valhalla integration).
- v2: regional pack downloader UI (replacing the manual bundle delivery of v1).
- v2: glamorous annotation pass (hand-drawn marker style, yellow highlighter band, red marker handwriting).
- v3+: atmospheric animations (parked idea, see [memory: project_v3_atmosphere.md](/Users/mlifshits/.claude/projects/-Users-mlifshits-work-AlaskaRouter/memory/project_v3_atmosphere.md)).

---

## How to rerun the spikes

### Spike B (search)

```sh
# Prereqs: brew install osmium-tool
cd spikes/B_fts5/build
./run.sh                       # filter OSM → export GeoJSON → build pois.sqlite
cd ../swift
swift run QueryTest            # runs the 12-case battery
```

### Spike A + C (rendering, PMTiles, expedition style)

```sh
# Prereqs: brew install xcodegen
#          defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
#          defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
cd spikes/A_maplibre
xcodegen generate
xcodebuild -project AlaskaRouterSpike.xcodeproj -scheme AlaskaRouterSpike \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath build \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
APP=build/Build/Products/Debug-iphonesimulator/AlaskaRouterSpike.app
xcrun simctl install booted "$APP"
xcrun simctl launch booted dev.alaskarouter.MapLibreSpike
```

To swap between the expedition style and the PMTiles smoke test, change the resource name in [ContentView.swift](spikes/A_maplibre/Sources/ContentView.swift) (`style-expedition` ↔ `style-pmtiles`).
