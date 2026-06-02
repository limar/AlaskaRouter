---
# AlaskaRouter-rydj
title: 'Stage 5 — Private directories: polite scraper + geocoder (ToS-gated)'
status: completed
type: task
priority: normal
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T12:29:54Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-l48r
---

Private/commercial campgrounds absent from gov sources. Legal-care required.

- [x] SCOPE REDUCED to ACOA only (user decision). sources/scrape_acoa.py: checks robots.txt FIRST (refuses if User-agent:* Disallow:/), descriptive UA, reads the member directory via the public wp-json REST API. Alaska Family Motorhomes / ACVB / Alaska.org DEFERRED (see follow-up note).
- [x] Parses the acoa-member-list Elementor blob into (name, street, city, AK, zip). 35 entries. phone/email/website/season NOT present on that page (would require crawling per-campground regional pages) — deferred; we capture name + address + region.
- [x] sources/geocode.py: cached Nominatim (UA w/ contact, 1.1s rate limit, data/geocode-cache.json caches hits AND misses). Falls back from full street address to City,AK,zip. booking_method left '' (no booking URL on the page; don't fabricate).
- [x] Emits data/source-acoa.jsonl (32 geocoded; 3 mile-marker addresses unresolved). ToS/robots posture documented in scrape_acoa.py header (robots Allow:/, Content-Signal search=yes/ai-train=no; our use is search-index). README runbook = Stage 6.
- [x] AllStays/Campendium (Apify) DEFERRED — paid SaaS, user avoids subscriptions. To be noted in README (Stage 6).
- [x] Acceptance PASS: 32 ACOA private campgrounds geocoded (all within AK bounds); robots checked + honored; rebuild 34,043 -> 34,068 (25 acoa rows survive, 7 collapsed into existing campgrounds).

## Summary of Changes

NEW sources/geocode.py (cached Nominatim) + sources/scrape_acoa.py. Adds private/commercial campgrounds — the one category missing from federal/state/OSM.

- 32 ACOA member campgrounds geocoded from street addresses -> data/source-acoa.jsonl; 25 survive dedup. Robots/Content-Signal checked and honored (search-index use is permitted; we don't train models).

### Scope decision
Stage was scoped by the user to ACOA only. The other directories from the original plan — Alaska Family Motorhomes RV lists, the legacy ACVB page, Alaska.org regional pages — were NOT done, and AllStays/Campendium remain deferred (paid SaaS). The scrape_acoa.py pattern (robots-check -> wp-json/HTML parse -> cached geocode -> SourceRecord) generalizes to those if wanted later.

### Limitations
- Coordinates are geocoded, so approximate (street-level where the address is clean; some are 'Mile NN highway' addresses). 3 entries did not geocode.
- phone/website/open_season not captured (not on the member-list page).
- Name extraction from the Elementor blob is heuristic; entries whose name contains a comma can mis-split (filtered out 'and …' fragments).

DB not yet swapped into Resources (Stage 6).
