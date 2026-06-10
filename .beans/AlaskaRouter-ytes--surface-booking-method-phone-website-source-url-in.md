---
# AlaskaRouter-ytes
title: Surface booking_method / phone / website / source_url in the app
status: scrapped
type: feature
priority: normal
created_at: 2026-06-02T12:39:09Z
updated_at: 2026-06-10T10:31:15Z
parent: AlaskaRouter-xtua
blocked_by:
    - AlaskaRouter-ief3
---

The places DB now carries v5 enrichment columns (phone, website, booking_method, open_season, source_url), populated for campgrounds/cabins/huts via the data work in AlaskaRouter-ief3. The app does not yet read or display them.

- [ ] Extend SearchService SELECT + SearchResult to read the v5 columns.
- [ ] Show booking_method as a chip in the stop callout + search row (Reservable -> open source_url; First-come; Call -> phone).
- [ ] Tappable phone (tel:) / website / recreation.gov booking link in the stop detail sheet.
- [ ] Consider a campgrounds-near-here category filter leveraging the richer camping(493)+cabin(293) coverage.

Non-blocking; the data already ships.
