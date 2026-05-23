---
# AlaskaRouter-22h7
title: Expand search DB with businesses + named POIs (beyond current Alaska places set)
status: in-progress
type: feature
priority: high
created_at: 2026-05-20T20:20:30Z
updated_at: 2026-05-23T12:34:16Z
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

- [ ] **Step 4: Drop-token relaxation + synonym injection** in `SearchService`. Drop-token: when stage 1 strict-AND yields zero, retry without the rarest token. Synonyms: small dictionary expanded inline (`sign ↔ marker, monument, wayside`; `rental ↔ rent, hire, adventures, outfitters`; `bike ↔ motorcycle, bicycle`; etc.).
- [ ] **Gate behind a runtime feature flag** so before/after can be flipped live and a regression doesn't require a code revert. Probably exposed in `TweaksStore` so we can play with it in the Tweaks panel.

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
