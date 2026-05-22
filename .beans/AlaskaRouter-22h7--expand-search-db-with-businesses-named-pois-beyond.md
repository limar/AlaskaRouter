---
# AlaskaRouter-22h7
title: Expand search DB with businesses + named POIs (beyond current Alaska places set)
status: todo
type: feature
priority: high
created_at: 2026-05-20T20:20:30Z
updated_at: 2026-05-21T15:12:09Z
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
