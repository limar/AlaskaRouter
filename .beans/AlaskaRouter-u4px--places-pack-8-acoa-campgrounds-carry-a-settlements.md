---
# AlaskaRouter-u4px
title: 'Places pack: 8 ACOA campgrounds carry a settlement''s exact coordinates'
status: completed
type: bug
priority: normal
created_at: 2026-07-30T17:42:55Z
updated_at: 2026-07-30T19:00:36Z
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
- [x] Root cause removed at source instead: the town-level fallback no longer fires (see below). Collision check deferred to v2.0 pipeline work.
- [x] All 8 hand-verified and corrected, plus a 9th (Bear Creek RV Park)
- [ ] Re-check the gnis/osm/wikidata collisions (5 more, other categories) — deferred, not campgrounds

## Summary of Changes

### Root cause
`scrape_acoa.py` retried a failed street-address geocode with everything after the first comma. For `"Alaska Hwy, Tok, AK 99780"` that still names a road — fine. For `"Willow, AK 99688"` it decays to a bare town, and the campground was stored at the town centre. Nothing recorded that precision had been lost, so in the app it looked identical to good data.

### Fix
1. **`sources/manual_coords.json`** (new) — hand-verified address → lat/lon, each with a checkable `source` string. Consulted *before* geocoding, so re-running the pipeline reproduces the corrections instead of reverting them.
2. **Town-level fallback rejected.** The retry now only runs when the remaining string still names a road. A bare town reads `"City, AK ZIP"` — one comma; anything naming a road keeps two or more. Cheap and exact.
3. Unresolved records are **dropped with a loud line**, never degraded to their town. There is no "approximate" tier.

A blanket removal of the fallback was tried first and over-corrected — it also dropped records that had been resolving to roads perfectly well.

### The nine corrected
| campground | was | now | source |
|---|---|---|---|
| Grizzly Lake Campground | Gakona centre, 72.9 km out | 62.713447, −144.198420 | OSM; "Gakona" was only its mailing town |
| Montana Creek Campground | Willow centre, 39.6 km out | 62.10354, −150.05846 | OSM; Mile 96.5 Parks Hwy ✓ |
| Ranch House Lodge & RV | Glennallen centre, 22.8 km out | 62.10238, −145.96829 | OSM; Glenn Hwy MP173 vs MP187 ✓ |
| Base Camp Kennicott | McCarthy centre, 6.2 km out | 61.434013, −142.943997 | basecampkennicott.com; Mile 59.4 by the footbridge |
| Homer Baycrest KOA | Homer centre, 5.6 km out | 59.657508, −151.641184 | Nominatim exact address match |
| Palmer/Anchorage N. KOA | **Palmer's exact coords** | 61.56125, −149.29221 | Good Sam + Yelp agree |
| Stoney Creek RV Park | Seward centre | 60.18048, −149.37906 | Good Sam; 4 directories within ~200 m |
| Birchwood Campground | Kasilof centre, 148 km out | 60.301485, −151.284861 | user-verified on Google Maps; confirmed within 500 m of OSM "North Cohoe Loop Road" |
| Bear Creek RV Park | *(would have been dropped)* | 60.184619, −149.372589 | camping.org / AAA — the only ACOA entry with no OSM equivalent |

### Dedup finally works on them
Several of these existed in the pack **twice**: a correct OSM row plus a phantom ACOA row at a town centre, unmerged only because they were further apart than `NAME_CLUSTER_KM = 5.0`. With positions corrected they collapse, `SOURCE_RANK` keeps OSM's canonical position, and `_BACKFILL` copies ACOA's phone/website into it — **Ranch House Lodge** and **Homer Baycrest KOA** are now enriched OSM rows rather than ghosts. The enrichment landed where it was always meant to.

### Verification
- Settlement-collision query on the rebuilt pack: **clean**, was 8.
- Nothing lost: the 5 still-unresolved entries (3 Denali, Kenny Lake, Seward KOA) are all already in the pack from OSM at proper positions. Checked individually.
- The ACOA member list has also grown since the June scrape: **net +15 campgrounds** (22 → 38 raw records).
- 133 tests green; verified in the app — no dot sits on Palmer any more.

Not done here, still v2.0: emitting the unresolved list as a build product, and the generic build-time collision guard.
