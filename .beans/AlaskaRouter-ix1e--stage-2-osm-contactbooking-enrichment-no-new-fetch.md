---
# AlaskaRouter-ix1e
title: Stage 2 — OSM contact/booking enrichment (no new fetch)
status: completed
type: task
priority: high
created_at: 2026-06-02T10:00:10Z
updated_at: 2026-06-02T10:51:10Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-l48r
---

Highest ROI, zero legal risk: stop discarding OSM contact tags for camp/lodging/hut rows.

- [x] filter_tags.sh: camp_site/caravan_site/alpine_hut/wilderness_hut/shelter already covered; added amenity=sanitary_dump_station (-> category dump_station). Takes effect on the next full re-filter (run.sh); not in the stale May-23 geojson used for this verification.
- [x] extract_contact(): harvests phone|contact:phone|contact:mobile, website|contact:website|url, opening_hours|opening_hours:camping|seasonal -> open_season, plus OSM source_url. Scoped to CONTACT_CATEGORIES = camping/lodging/hut/picnic/ranger_station/visitor_center. NOTE: `operator` not stored (no column yet).
- [x] booking_method ladder (conservative): reservation=no -> no_reservations; reservation in {required,yes,recommended,members_only,online} -> online_portal(if website)/phone_email(if phone)/unknown; fee=no -> walk_in; else ''. DEVIATION from the loose spec: we do NOT assert online_portal from a bare homepage nor phone_email from a bare phone tag (avoid fabricating booking semantics — house rule). phone/website are still stored so the app can show 'call to book' when booking_method=''.
- [x] Acceptance PASS: total unchanged (33,470). Non-empty fills: phone 188, website 396, booking_method 168 (online_portal 63 / unknown 41 / walk_in 34 / no_reservations 27 / phone_email 3), open_season 24, source_url 1,313. Spot-checked Girdwood Campground, Moon Lake SRS, Russian River — real phone/website/OSM link.

## Summary of Changes

Stops discarding OSM contact/booking tags for overnight/trip POIs; behavior-preserving for row counts.

- build_fts5.py: new extract_contact(tags, osm_type, osm_id) + CONTACT_CATEGORIES; wired into the OSM candidate build so camping/lodging/hut/picnic/ranger_station/visitor_center rows populate the v5 columns. Conservative booking_method derivation (see checklist).
- filter_tags.sh: + amenity=sanitary_dump_station (category dump_station); effective on next full re-filter.
- BUG FIX (pre-existing): the OSM id is at the GeoJSON Feature top level (feat['id']='n420361886'), not properties['@id'] — so EVERY OSM row had been stored osm_type='unknown'/osm_id=0 (confirmed: all 15,271 OSM rows in the shipped DB). Now reads feat['id'] first; osm_type is real (node 9,581 / way 4,630 / unknown 1,060) and source_url can be built. No effect on `source` (still 'osm') or dedup (keys on name+coords), so counts are unchanged.

Verified against the existing filtered GeoJSON (no re-filter). dump_station + any newer OSM coverage will appear on the next full run.sh; DB not yet swapped into Resources (Stage 6).
