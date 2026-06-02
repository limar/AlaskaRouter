---
# AlaskaRouter-lzrh
title: Stage 6 — Cross-source dedup tuning, QA, README runbook, ship
status: todo
type: task
priority: normal
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T10:01:06Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-ix1e
    - AlaskaRouter-lyog
    - AlaskaRouter-76iz
    - AlaskaRouter-rydj
---

Merge quality + reproducibility + ship.

- [ ] Extend dedup: add shared-URL match and (where available) shared external-ID match on top of existing proximity+name clustering. Confirm source-priority: federal > state/local > OSM > GNIS > Wikidata > private.
- [ ] Contact-field conflict resolution: highest-priority non-empty wins; backfill empties from lower-priority duplicates before discarding them.
- [ ] sources/qa_report.py: per-source counts, % with coords / booking_method / phone, duplicates collapsed, sample around the planned AK route.
- [ ] Update tools/build-places/README.md: full re-collection runbook (env vars incl. RIDB key, robots/ToS posture, expected counts, troubleshooting) + extend run.sh to call every fetcher.
- [ ] Swap rebuilt DB into AlaskaRouter/Resources/alaska-places.sqlite; smoke-test in-app campground search.
- [ ] Offer follow-up bean: surface booking_method/phone/website in stop callout + search results (app-side, non-blocking).
