---
# AlaskaRouter-lyog
title: 'Stage 3 — Federal: RIDB / Recreation.gov fetcher'
status: todo
type: task
priority: high
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T10:01:05Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-l48r
---

sources/fetch_ridb.py — authoritative federal campgrounds + recreation facilities.

- [ ] Read RIDB_API_KEY from env; fail loudly with acquisition instructions if absent (free key from ridb.recreation.gov). Document in README.
- [ ] GET /api/v1/facilities?state=AK paginated (limit/offset); optionally /campsites, /media (photos), /links (reservation URLs).
- [ ] Map FacilityTypeDescription => category: campgrounds => camping; keep non-camping (visitor centers, trailheads, boat launches, picnic) into existing categories.
- [ ] Emit data/source-ridb.jsonl in the common format: name, FacilityLatitude/Longitude, FacilityPhone/Email, FacilityURL, reservation URL => booking_method=online_portal else first-come text => walk_in, first photo => (parked; photos_url not in v1 schema), source_url.
- [ ] Idempotent (skip if file present; --force). 429/5xx exponential backoff matching fetch_wikidata.py etiquette.
- [ ] Acceptance: AK federal campgrounds + facilities ingested; dedup vs OSM by name+proximity collapses overlaps.
