---
# AlaskaRouter-b7g0
title: 'Search results: replace lat/lon with admin-area context line'
status: in-progress
type: feature
priority: high
created_at: 2026-05-24T18:54:28Z
updated_at: 2026-05-25T07:07:34Z
parent: AlaskaRouter-xtua
---

## Problem

Search-results dropdown currently shows:

```
[icon] Name
       category · 64.123, -149.456
```

Lat/lon are useless to humans. The user wants Google-Maps-style admin context — *"Eagle Plains / YT, Canada"*, *"American Eagle Store / Weizmann Street, Kefar Sava, Israel"*, *"Eagle Beach / Aruba"* — so they can disambiguate "Yukon River camping" between Alaska and Canada at a glance.

For v1 (Alaska only), the natural unit is the **borough / census area**. Alaska has ~30 of them, all distinctive ("Denali Borough", "Fairbanks North Star Borough", "Yukon-Koyukuk Census Area", "Juneau, City and Borough of"). State + country is redundant — everything in v1 is Alaska, USA.

## What we already have

`place_meta` columns today: name, category, lat, lon, importance, alt_names, source. **No direct admin fields.**

But:
- **GNIS** has a `county_name` column in `DomesticNames_AK.txt` we currently DISCARD. ~12,630 post-dedup rows ship with known borough/census-area info if we just stop dropping it.
- **OSM** features have admin parents via OSM relations (admin_level 4=state, 6=county/borough, 8=city). Not extracted at filter time.
- **Wikidata** items have P131 ("located in administrative entity"). Could add to the SPARQL query.
- **All sources** have lat/lon — so we can compute "nearest GNIS row's county" as a fallback for non-GNIS rows. Cheap.

## Heuristic ladder

| Effort | Approach | Coverage |
|---|---|---|
| Free | Drop the lat/lon string, show category only | doesn't solve the problem |
| **Easy** | Keep GNIS's `county_name`; non-GNIS rows inherit from nearest GNIS row within 30 km | ~95 % (Alaska is GNIS-dense) |
| **Easy+** | Same as Easy + show "near {settlement}" prefix when a settlement is within 10 km | same coverage, richer line |
| Moderate | Extract OSM admin relations via a second osmium pass | ~100 % for OSM; falls back to nearest-GNIS for GNIS/Wikidata. Most accurate. |
| Moderate+ | TIGER county shapefiles + point-in-polygon | 100 % authoritative, source-agnostic. New shapefile + geometry dep. |
| Future v2+ | Real country/state hierarchy for multi-region packs | required when we generalize beyond Alaska |

## Proposed Phase 1 (this bean)

**Easy + Easy+.** Smallest change that fixes the user-visible problem:

1. **Schema** — add `admin_area TEXT NOT NULL DEFAULT ''` to `place_meta`. Bump version to v4. Additive — no migration risk.
2. **GNIS pass** — keep `county_name` verbatim from the source. Already in the file; just stop dropping it.
3. **Inheritance pass** — for each non-GNIS row, find the nearest GNIS row with non-empty `admin_area` within 30 km; adopt its `admin_area`. O(N·M) with a bbox prefilter; ~30 s extra build time.
4. **Optional: nearest-settlement prefix** — find the closest row with category in {settlement_major, settlement} within 10 km; store as `nearest_settlement` (new column). UI shows "near {settlement} · {admin_area}". Skip if the row IS itself a settlement.
5. **SearchResultsView** — drop the lat/lon string. Render `admin_area` (with optional "near X" prefix) in its place. Hide the line entirely when `admin_area` is empty (rare).

## Architecture — open questions

1. **"County" suffix**: keep verbatim ("Denali Borough", "Yukon-Koyukuk Census Area") or strip ("Denali", "Yukon-Koyukuk")? Verbatim is more correct, stripped is less verbose. **Recommendation: verbatim.**
2. **"near {settlement}" prefix in Phase 1 or defer?** Adds a small extra build pass; materially better UX. **Recommendation: ship.**
3. **Nearest-GNIS radius — 30 km.** Alaska is GNIS-dense; this should cover ~95 % of non-GNIS rows. **Confirm.**
4. **Empty `admin_area` fallback** — hide the line, or show "Alaska, USA"? **Recommendation: hide. Everything in v1 is Alaska, USA, so the fallback would be universal noise.**
5. **Schema v3 → v4** — additive (no destructive change). Existing builds keep working until the build script re-runs. **Confirm.**

## Out of scope (defer to v2+ multi-region bean)

- Country / state hierarchy
- Locale-aware admin names ("Yukon Territory" vs "Territoire du Yukon")
- OSM admin-relation extraction (would do this if Phase 1's nearest-GNIS heuristic produces too many empty lines in practice)

## Checklist

- [ ] Lock the 5 open architecture questions
- [ ] Schema: add `admin_area TEXT NOT NULL DEFAULT ''` (+ optional `nearest_settlement TEXT`) to place_meta, bump SCHEMA_VERSION to 4
- [ ] GNIS: keep county_name verbatim
- [ ] Inheritance pass: bbox-prefiltered nearest-GNIS lookup for non-GNIS rows
- [ ] Optional: nearest-settlement pass for the prefix
- [ ] SearchResultsView: replace coord string with `admin_area` (+ optional prefix)
- [ ] Rebuild DB, copy into bundle, verify on device


## Decisions locked (2026-05-25)

1. **Borough/county format:** stripped — "Denali", "Yukon-Koyukuk", "Sitka", "Juneau".
2. **"near {settlement}" prefix:** deferred to a later bean.
3. **Inheritance radius:** 30 km, confirmed.
4. **Empty-admin fallback:** show "AK, USA" — universal in v1 but distinguishes from adjacent Canada (many shared toponyms — Yukon River etc.) and forward-compats v2+ ("Rajasthan, India" pattern).
5. **Schema v3 → v4:** additive, confirmed.

## Summary of Changes

**Build pipeline (`build_fts5.py`):**

- Schema bumped to v4. New column `admin_area TEXT NOT NULL DEFAULT ''` on `place_meta`.
- New helper `strip_borough_suffix(s)`: collapses GNIS `county_name` variants into a single canonical form. Handles `" Borough"`, `" Census Area"`, `" Municipality"`, `" City and Borough of"`, `" City"`, `(CA)`, `(Census Area)` parentheticals — both as suffixes and as residuals after another suffix gets stripped.
- `gnis_candidates` now emits a 9-tuple including the stripped county; OSM and Wikidata candidates emit the same shape with an empty admin slot.
- New post-dedup **pass 2c**: for each non-GNIS row, find the nearest GNIS donor row within 30 km via an integer-degree-lat-banded hash (cheap bbox prefilter) + haversine on the surviving subset, adopt its `admin_area`. Coverage: **33,235 / 33,470 rows (99.3 %) have admin info; 20,607 inherited from nearest GNIS within 30 km.**
- INSERT writes the new column.

**Swift app:**

- `SearchResult` gains `adminArea: String`.
- SQL JOIN selects `m.admin_area` as column 7 (across both stage 1 and stage 2 queries).
- `readRow` reads column 7 and passes through to `SearchResult.init`.
- `SearchResultsView` replaces the `lat, lon` line with `locationLine(for:)` — returns `"{adminArea}, AK, USA"` when admin is known, else `"AK, USA"`.

**Result distribution** (top boroughs, post-merge):

```
Yukon-Koyukuk   2732
Aleutians West  2709
Kenai Peninsula 2468
Matanuska-Susitna 2153
Prince of Wales-Hyder 2099
Anchorage       1932
Nome            1308
Aleutians East  1302
Sitka           1244
Fairbanks North Star 938
Juneau          779
…
(no admin)      235     ← shows "AK, USA" fallback
```

DB size: 8.3 MB → 8.4 MB.

- [x] Lock the 5 open architecture questions
- [x] Schema bump to v4, add `admin_area`
- [x] GNIS pass: keep county_name with stripped suffix
- [x] Inheritance pass: nearest-GNIS within 30 km for non-GNIS rows
- [x] SearchResultsView: replace coord string with location line
- [ ] On-device verify
