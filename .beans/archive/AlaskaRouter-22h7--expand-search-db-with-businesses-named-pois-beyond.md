---
# AlaskaRouter-22h7
title: Expand search DB with businesses + named POIs (beyond current Alaska places set)
status: completed
type: feature
priority: high
created_at: 2026-05-20T20:20:30Z
updated_at: 2026-05-23T14:41:14Z
parent: AlaskaRouter-xtua
---

Current alaska-places.sqlite (12k entries) misses everyday-important POIs. User reported: 'Last Frontier Motorcycle Adventures' (bike rental, North Pole AK) and 'Arctic Circle Sign' (photo-op landmark on Dalton Highway) — both absent. v1 fix: enrich Alaska coverage. v2+ goal: per-region search packs for any state/country on earth.

## User report (verbatim)

> "I couldn't find Last Frontier Motorcycle Adventures (the place where I'm going to rent the bike, North Pole) and Arctic Circle Sign (where everybody stops to take a photo and decide they're continuing to Deadhorse or not)."

Both are real, named, well-known places — they should be findable. Their absence is symptomatic of a broader gap: the current 12 k Alaska places set was built from a single source (likely OSM admin/POI export) and misses everyday business listings + soft landmarks.

## v1 fix — enrich Alaska coverage

Sources to investigate, in order of likely yield:
1. **OSM `amenity=*` businesses** — current set may have filtered out commercial nodes. Re-extract with broader `amenity` whitelist (`fuel`, `restaurant`, `lodging`, `bike_shop`, `motorcycle_rental`, etc.).
2. **OSM named features that aren't admin boundaries or peaks** — `tourism=*`, `historic=*`, `attraction=*` likely contain the Arctic Circle Sign and similar.
3. **Wikidata's "things named X in Alaska"** — name-rich, geo-tagged, free.
4. **Manual curation list** — for high-value places we know users want and OSM doesn't have, a small hand-curated JSON in the bundle.

## v2+ goal — per-region search packs

When the app generalizes beyond Alaska, search data should follow the same pack model as tile data:
- One `places-<region>.sqlite` per region pack
- Fetched on-demand from GitHub Releases (same workflow as 76y3 tile packs)
- Multi-region search service queries all installed packs

Architecturally, the current `SearchService` should accept an array of databases, not just one.

## Checklist

- [ ] Confirm Last Frontier Motorcycle Adventures + Arctic Circle Sign absent in current DB (`sqlite3 alaska-places.sqlite "SELECT * FROM places WHERE name LIKE '%Frontier%' OR name LIKE '%Arctic Circle%'"`)
- [ ] Re-extract OSM with broader category whitelist; measure how many entries we add
- [ ] If still missing the specific user-cited POIs, add manual-curation JSON
- [ ] Rebuild bundled `alaska-places.sqlite`
- [ ] Search for "Last Frontier", "Arctic Circle", "bike rental" — verify hits
- [ ] (v2+) Multi-pack architecture for SearchService

## Related

- AlaskaRouter-cv05 — display Arctic Circle line on map (complementary; one is the line, this is the named photo-stop)


## Plan (locked 2026-05-23)

After auditing the existing pipeline (`spikes/B_fts5/build/`) and confirming the two reported misses (`Last Frontier Motorcycle Adventures` and `Arctic Circle Sign`) against the bundled `alaska-places.sqlite` (12,617 entries), the design splits into two milestones:

### Milestone 1 — coverage

- [x] **Step 1: Widen the OSM whitelist** — delivered. 12,617 → 17,067 entries (+35 %). New categories `park` (668), `marina` (496), `viewpoint` 125 → 2,805 (coastal natural features). Real libraries, ferry terminals, parks, breweries, guide services, monuments now indexed. Schema bumped to v3 with new `source` column (defaults to `osm`; ready to receive `gnis` rows in step 2). Confirmed still-missing items are matcher-gap (`Ferry Whittier`) or OSM-coverage-gap (`Last Frontier Motorcycle Adventures`, `Arctic Circle Sign`) — both for later milestones.
- [x] **Step 2: Merge USGS GNIS Alaska** — delivered. 17,067 → 33,406 entries (+96 %). New `lake` category (3,433 entries). Major fills: `viewpoint` +5,012 (capes/bays/beaches/channels/gut/bar), `peak` +3,522 (summits/ridges/gaps), `island` +2,690, `glacier` +655. Brooks Range, Mt. McKinley, Wonder Lake, Atigun Pass, Hatcher Pass, Cantwell/Nenana/Susitna Glaciers, etc. all now findable. Skipped GNIS `Stream` class (9.3 k Alaska creeks, low individual signal) — Yukon River and other major rivers remain absent and will be revisited if missed in practice.
- [x] **Tooling: promote** the pipeline from `spikes/B_fts5/build/` to `tools/build-places/`, parallel to `tools/build-pack/`. `git mv` of the four scripts, `mv` of the 500 MB gitignored `data/` tree, `.gitignore` updated, README added matching the build-pack style, script-internal paths fixed (data is now `./data/` not `../data/`), pipeline rerun verified — same 33,406 places. **Milestone 1 complete.**

### Milestone 2 — matcher (after milestone 1 verified)

- [x] **Step 4: Drop-token relaxation + synonym injection** in `SearchService` — delivered. New `SearchStage` enum (.strict / .editDistance / .synonyms / .droppedTokens). Pipeline becomes: strict → (if loose) synonyms-expanded → (if loose & has droppable tokens) drop + synonyms → edit-distance. Synonym groups: bike↔motorcycle↔bicycle, mountain↔mount↔mtn, camp↔campsite↔campground, sign↔marker↔monument↔wayside↔memorial, rental↔rent↔hire↔rentals, ferry↔ferries, gas↔fuel↔petrol↔diesel, airport↔airfield↔airstrip, peak↔summit, lodge↔inn↔hostel↔motel↔hotel, bay↔cove, store↔shop↔market. Droppable descriptors: ferry, sign, marker, rental/rentals/rent/hire, the/of/at/in/and/to/a/an. FTS expression switches joiner to explicit `AND` when any group is parenthesized (FTS5 implicit-AND only works on bare token sequences). Verified at SQL level: "Arctic Circle Sign" → synonyms find "Arctic Circle Wayside"; "camping near Denali" → drop-token finds Denali campings; "rent a kayak" → drop-token finds Kayak Cove, Kayak Mountain.
- [x] **Gate behind a runtime feature flag** — `TweaksStore.useLooseMatcher` (persisted, default ON). Toggle in `TweaksPanel`'s new Search section with a footnote explaining what it does. `SearchService.setQuery` snapshots the flag on the MainActor and passes it to the nonisolated search task. Result rows in `SearchResultsView` get a per-stage indicator: "fuzzy ±N" for edit-distance (unchanged), "synonym" for synonym-expanded, "loose" for drop-token; nothing shown for strict.

### Out of scope this round

- Manual curated overlay (step 3) — user not ready for manual curation.
- Wikidata enrichment (step 5) — defer until milestones 1+2 land and we measure remaining gaps.
- Multi-pack architecture — separate bean `AlaskaRouter-rwbc`, deferred to v2+.
- Moving the DB out of git — keep bundled (`AlaskaRouter/Resources/alaska-places.sqlite`).

### Source of truth for the search DB

Confirmed pipeline: `spikes/B_fts5/build/run.sh` → `filter_tags.sh` (osmium tags-filter) → `build_fts5.py` (osmium export GeoJSON → SQLite FTS5). Categorizer + importance table + alt-names harvesting are in `build_fts5.py`.

Schema:
- `place_meta(rowid, osm_type, osm_id, lat, lon, category, importance, name, alt_names)` — adding `source TEXT NOT NULL DEFAULT 'osm'` in milestone 1.
- `places_word` FTS5 virtual table over (`name`, `alt_names`, `category`, `region`).
- `metadata` table — extending with per-source row counts + MD5s.


## Step 5 — Wikidata (added in same session by user request)

Wikidata's WDQS has  21,600 Alaska-located items with coordinates  — a different
slice from OSM (businesses + landmarks) and GNIS (US natural-feature names).
Wikidata fills the long tail of culturally / historically named places:
  - Indigenous villages (Savoonga, Hydaburg, Chevak, Brevig Mission, Adak,
    Holy Cross, Kaktovik Village, Egegik, Gustavus, Dillingham, Scammon Bay…)
  - Famous landmarks (Aleutian Range, Aleutian Islands, Sitka Historical Museum,
    Mount Juneau, Iditarod Trail Sled Dog Museum)
  - Multilingual entries

- [x] **fetch_wikidata.py** — SPARQL via WDQS, transitive `wdt:P131* wd:Q797`.
  Raw rows (no aggregation) so the query finishes inside WDQS's 60s timeout;
  Python dedupes per-item with set-of-types. Output: `data/wikidata-ak.jsonl`
  (21,078 items). Idempotent. Retry-on-429 with backoff.
- [x] **build_fts5.py wikidata_candidates()** — reads the .jsonl, maps types to
  categories using word-boundary regex matching (the substring approach false-
  matched 'ridge' inside 'bridge', etc.). Settlements explicit first (so
  'borough seat' and 'unincorporated community' don't get dropped by the
  admin-filter on 'borough' / 'unincorporated'). Skips items whose type can't
  be cleanly bucketed.
- [x] **Counts after the three-way merge:** 33,406 → **42,913 places** (+9,507
  net new entries, +28 % on top of milestone 1; cumulative +240 % vs the pre-
  22h7 baseline of 12,617). Source breakdown: OSM 17,036, GNIS 16,308,
  Wikidata 9,569. DB size 8.2 → 10.6 MB.
- [x] **run.sh** picks up `./fetch_wikidata.py` so a clean rebuild fetches
  Wikidata alongside GNIS.

**Milestone 1 (coverage) is now complete with all three sources merged.**


## Summary of Changes

Three-source places DB rebuild + a runtime-toggleable loose matcher in the app. Shipped as five focused commits:

1. **Wider OSM filter** (`52f369d`) — 12,617 → 17,067 (+35 %). New OSM tag families: `amenity` rentals/ferry/library, `tourism` artwork/gallery, `man_made` monument/sign/cairn/pier, `natural` coastal features, `leisure` parks/marinas, `boundary` national_park, `craft` brewery/winery, `office` guide. Schema bumped to v3 with new `source` column.
2. **USGS GNIS merge** (`100232b`) — 17,067 → 33,406 (+96 %). New `lake` category (3,433 entries). Fills the long-tail natural-feature gap (Brooks Range, Wonder Lake, Mt. McKinley, Atigun Pass, named glaciers/capes/bays). Skipped `Stream` class (9.3 k Alaska creeks — too noisy individually).
3. **Pipeline promotion** (`7054864`) — `spikes/B_fts5/build/` → `tools/build-places/` parallel to `tools/build-pack/`. README mirrors the build-pack style.
4. **Loose matcher** (`c64e92b`) — New `SearchStage` enum and four-stage pipeline gated behind `TweaksStore.useLooseMatcher` (default ON, toggleable in `TweaksPanel`'s new Search section). Synonym groups: bike↔motorcycle, sign↔wayside, ferry↔ferries, peak↔summit, gas↔fuel, etc. Droppable descriptors: ferry, sign, rental, the/of/at/in/and/to/a/an. Result rows get a per-stage indicator: "fuzzy ±N" (edit-distance), "synonym", "loose".
5. **Wikidata** (`b635198`) — 33,406 → **42,913 places** (+28 %, cumulative **+240 % vs the pre-22h7 baseline of 12,617**). Fills indigenous communities (Savoonga, Hydaburg, Adak, Holy Cross, Kaktovik Village…), famous landmarks (Sitka Historical Museum, Iditarod Trail Sled Dog Museum, Aleutian Range, Mt. Juneau), and multilingual entries.

DB size: 2.9 MB → 10.6 MB. Source breakdown after dedup: OSM 17,036, GNIS 16,308, Wikidata 9,569.

### What still misses (deferred, not blocking)

- `Last Frontier Motorcycle Adventures` — not in OSM, GNIS, **or** Wikidata. Would require step 3 (curated overlay) — the user explicitly declined to do manual curation at this milestone.
- `Arctic Circle Sign` — works now via the loose matcher (synonym `sign↔wayside` finds "Arctic Circle Wayside"). Original literal entry still absent from all three sources.

### Related beans still open

- `AlaskaRouter-rwbc` — multi-region search (combine FTS5 DBs across packs). Architecturally distinct; deferred to v2.
