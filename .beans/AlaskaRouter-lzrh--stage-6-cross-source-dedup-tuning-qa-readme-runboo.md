---
# AlaskaRouter-lzrh
title: Stage 6 — Cross-source dedup tuning, QA, README runbook, ship
status: completed
type: task
priority: normal
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T12:39:53Z
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
