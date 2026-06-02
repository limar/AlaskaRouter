---
# AlaskaRouter-lyog
title: 'Stage 3 — Federal: RIDB / Recreation.gov fetcher'
status: completed
type: task
priority: high
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T12:05:45Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-l48r
---

sources/fetch_ridb.py — authoritative federal campgrounds + recreation facilities.

- [x] require_env('RIDB_API_KEY') in common.py loads tools/build-places/.env then env; fails loud with the get-a-key hint. (README runbook is Stage 6.)
- [x] GET /facilities?state=AK with sort=Name + large limit. /campsites + /media (photos) NOT pulled: photos_url is not in the v5 schema and campsite-level detail is out of scope for a gazetteer (deferred). FacilityReservationURL is empty for all AK rows; booking is by FacilityID.
- [x] classify(name, ftype): keyword ladder (cabin/trailhead/boat_launch/visitor_center/ranger_station/picnic/viewpoint/park/camping) then ftype fallback. Permit + Ticket Facility dropped (non-spatial booking products). smart_title() fixes ALL-CAPS RIDB names. Result: cabin 185, park 38, camping 12, picnic 2, visitor_center 1, trailhead 1 (after dedup).
- [x] Emits data/source-ridb.jsonl (262 records). booking_method=online_portal when Reservable (204); source_url = recreation.gov/camping/campgrounds/{id} for reservable, else FacilityMapURL (236 filled); phone 194. Email dropped (no column). walk_in NOT inferred (Reservable=false left unknown — don't fabricate).
- [x] Idempotent (skips when output present; --force refetches). 429/500/502/503/504 retried with exponential backoff + Retry-After.
- [x] Acceptance PASS: rebuild 33,470 -> 33,662 (+192). 239 RIDB rows survive (23 collapsed into OSM/GNIS; 45 lower-importance OSM rows upgraded to RIDB cabins w/ booking). Spot-checked Caribou Creek / Romig / McKinley Lake cabins -> online_portal + rec.gov deep-link.

## Summary of Changes

NEW sources/fetch_ridb.py — federal Recreation.gov facilities for AK via RIDB.
- common.py gained load_env()/require_env() (.env loader, fail-loud) + DATA_DIR/BUILD_PLACES_DIR/ENV_FILE constants, shared by all fetchers.
- 262 normalized records -> data/source-ridb.jsonl; merged via the data/source-*.jsonl glob. 185 public-use cabins survive with online_portal booking + recreation.gov deep-links (high trip value).

### Findings / decisions
- **RIDB offset paging is UNSTABLE without sort**: an unsorted full pass returned 277 rows but only ~233 unique (distinct facilities silently missed). Fixed with sort=Name (+ large page). Worth remembering for any other RIDB state pulls.
- ALL-CAPS facility names title-cased (smart_title) preserving acronyms.
- Permit/Ticket-Facility rows (road lotteries, tours, permit bundles) and 8 ungeocoded rows dropped.
- **Cross-source field loss is deferred to Stage 6**: external rows are appended after OSM/GNIS/Wikidata, so dedup currently picks the highest-IMPORTANCE representative, not the highest source-priority one, and does NOT backfill empty contact fields from collapsed duplicates. Net effect today: a few federal campgrounds that also exist in OSM keep the OSM row and lose RIDB's booking link. Stage 6 (AlaskaRouter-lzrh) introduces real source priority + empty-field backfill.

DB not yet swapped into Resources (Stage 6).
