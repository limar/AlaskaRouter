---
# AlaskaRouter-u4px
title: 'Places pack: 8 ACOA campgrounds carry a settlement''s exact coordinates'
status: todo
type: bug
priority: normal
created_at: 2026-07-30T17:42:55Z
updated_at: 2026-07-30T17:42:55Z
parent: AlaskaRouter-36of
---

Surfaced while investigating AlaskaRouter-35z7's follow-up. "Palmer/Anchorage N. KOA" sits at `61.5995703, -149.11109` — byte-identical to the Palmer settlement row. The campground is real (it's a genuine KOA), but it is **not** at the city centroid; it has been geocoded to the town rather than to itself.

## Scope
```sql
SELECT c.source, COUNT(*) FROM place_meta c JOIN place_meta s
  ON c.lat = s.lat AND c.lon = s.lon AND c.rowid != s.rowid
WHERE c.category='camping' AND s.category IN ('settlement','settlement_major')
GROUP BY c.source;
-- acoa | 8
```
All 8 are from the **acoa** source (`akcampgrounds.com`, the Stage-5 polite-scraper + geocoder path, AlaskaRouter-rydj). Widening past campgrounds: acoa 8, gnis 2, osm 2, wikidata 1 — so it is overwhelmingly an ACOA geocoding artifact, not a general pipeline fault.

Affected: Montana Creek Campground (Willow), Grizzly Lake Campground (Gakona), Palmer/Anchorage N. KOA (Palmer), Base Camp Kennicott (McCarthy), Ranch House Lodge and RV Camping Resort (Glennallen), Stoney Creek RV Park (Seward), Birchwood Campground (Kasilof), Homer Baycrest KOA (Homer).

## Why it matters
A stop added from one of these lands the user at a town centre rather than the campground — a navigation error, not a cosmetic one. Exactly the class of failure that made us reject Google's name-search hand-off in AlaskaRouter-rvzg.

## Options
- **Detect and flag at build time.** Cheapest and most valuable: make `tools/build-places` fail (or warn loudly) when an ingested POI lands on an existing settlement's exact coordinates. Catches the whole class, including future sources.
- **Re-geocode the 8 from a better source.** OSM has some of these; the rest may need manual coordinates.
- **Drop them.** They are real places and worth having — a wrong location is worse than absence, but so is losing a genuine campground. Prefer fixing.

## Todo
- [ ] Add the exact-coordinate-collision check to the build pipeline
- [ ] Re-geocode or hand-place the 8 affected campgrounds
- [ ] Re-check the gnis/osm/wikidata collisions (5 more, other categories)
