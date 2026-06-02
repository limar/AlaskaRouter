---
# AlaskaRouter-rydj
title: 'Stage 5 — Private directories: polite scraper + geocoder (ToS-gated)'
status: todo
type: task
priority: normal
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T10:01:05Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-l48r
---

Private/commercial campgrounds absent from gov sources. Legal-care required.

- [ ] sources/scrape_directories.py: robots.txt check FIRST per host (skip host if disallowed), descriptive User-Agent, >=1 req/s rate-limit. Each site individually toggleable; conservative defaults.
      Targets: ACOA (akcampgrounds.com), Alaska Family Motorhomes RV lists, ACVB legacy (alaska.net/~acvb), Alaska.org regional pages.
- [ ] Parse HTML tables/cards => name, address, city, phone, email, website, open_season.
- [ ] sources/geocode.py: keyless Nominatim (proper UA, 1 req/s) to fill coords from address; persistent data/geocode-cache.json so re-runs are cheap. booking_method=phone_email default; online_portal if booking URL present.
- [ ] Emit data/source-<site>.jsonl; document ToS/robots posture per site in README.
- [ ] AllStays/Campendium (Apify) explicitly DEFERRED (paid SaaS; user avoids subscriptions) — note in README.
- [ ] Acceptance: private campgrounds with coords added; no robots violations; dedup against gov sources.
