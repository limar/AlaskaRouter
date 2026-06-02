---
# AlaskaRouter-lzrh
title: Stage 6 — Cross-source dedup tuning, QA, README runbook, ship
status: completed
type: task
priority: normal
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T13:04:43Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-ix1e
    - AlaskaRouter-lyog
    - AlaskaRouter-76iz
    - AlaskaRouter-rydj
---

Merge quality + reproducibility + ship.

- [x] Source priority implemented: SOURCE_RANK (ridb 0 > state/local 1 > osm 2 > gnis 3 > wikidata 4 > acoa 5); reduce_cluster() picks winner by (importance, then rank). Shared-URL/external-ID dedup EVALUATED + SKIPPED: providers don't share URLs/IDs cross-source, so name+proximity already catches real dups (documented in README).
- [x] reduce_cluster() backfills the winner's EMPTY contact fields from collapsed dups in source-priority order, and unions alt_names (+ folds losing-source names in) for recall. Unit-tested: OSM+RIDB collision -> RIDB wins, keeps online_portal+rec.gov url, gains OSM alt_names.
- [x] sources/qa_report.py: per-source + overnight-category fill rates + booking distribution + campground/cabin coverage around 8 route anchors + provenance. (camping 493 / cabin 293 / hut 136; cabins 72% booking, 97% source_url; Seward 39, Kenai 25 within 25km.)
- [x] README rewritten: 8-source table, RIDB key setup (.env), per-source endpoints + expected yields + robots/ToS posture, dedup/backfill explanation, v5 schema. run.sh now runs all fetchers then qa_report.py.
- [x] Swapped DB into AlaskaRouter/Resources/alaska-places.sqlite (8.9 MB, WAL-checkpointed single file, integrity_check ok). DB-level smoke test of the app's FTS query passes ('russian river' -> federal Russian River campground w/ online_portal + KPB one). Full in-app visual test recommended to the user.
- [x] Follow-up bean created: AlaskaRouter-ytes (surface booking_method/phone/website/source_url in the app), under v1 milestone, blocked-by this feature.

## Summary of Changes

Finalized the merge quality, documented the whole effort, and shipped the DB.

- build_fts5.py: SOURCE_RANK + reduce_cluster() — source-priority winner selection with cross-source contact backfill and alt_names union; both dedup passes (2a coord-key, 2b name-cluster) now route through it. Total stays 34,068; external rows that are authoritative now win collisions over OSM (KPB 54->81, RIDB 236->261, DNR 201->243 survive as canonical, OSM names preserved in alt_names).
- sources/qa_report.py (new); run.sh runs every fetcher + qa_report; README full runbook.
- Swapped alaska-places.sqlite into the bundle.

Final DB: 34,068 rows across 8 sources. Camping 388->493, cabins 0->293, huts ->136. booking_method on 374 rows (online_portal 256).

## Reopened — fuzzy cross-source dedup (AlaskaRouter-lzrh)

The exact-name dedup left ~150 cross-source near-duplicate pairs within 250 m
(e.g. 'Beaver Flats Campsite'[osm] vs 'Beaver Flats'[blm]; 'Swan Lake Cabin
Seward'[ridb] vs 'Swan Lake Cabin'[osm]). Measured: of 460 external overnight
rows, 97 overlap an OSM campground/cabin/hut. Adding a normalized-name spatial
merge pass.

- [x] Pass 2c added: union-find merge of MERGE_CATS (camping/cabin/hut) rows within 250 m whose normalized names are compatible (equal / token-prefix / Levenshtein<=2; generic tokens campsite/campground/cabin/(ak)/etc. stripped). reduce_cluster picks the authoritative survivor and backfills booking + alt_names.
- [x] Rebuild: 34,068 -> 33,977 (91 fuzzy-merged). Cross-source near-dup pairs within 250 m: 150 -> 32 (-79%). Remaining 32 are correctly distinct (e.g. 'Gut Island 1 Cabin' vs 'Gut Island 2 Cabin' stay separate) or too-generic-to-merge safely. Survivors gained OSM names as aliases + walk_in/booking.
- [x] DB re-swapped (33,977 rows, integrity ok). qa_report: camping 433 / cabin 286 / hut 112; camping source_url 96%, cabin 97%; booking online_portal 251.

## Update — fuzzy dedup landed

Closed the cross-source near-duplicate gap that the earlier exact-name dedup left. Pass 2c (build_fts5.py) does a tight spatial + normalized-name union merge for recreation overnight POIs, routed through reduce_cluster so the authoritative source wins and booking/alt_names carry over. 91 duplicates collapsed; near-dup pairs cut 150->32 with no observed over-merging. Final DB: 33,977 rows.
