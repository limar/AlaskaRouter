---
# AlaskaRouter-0z7e
title: Universal map landmark clickability (cities, peaks, gas, lakes, …)
status: todo
type: feature
priority: high
created_at: 2026-05-19T07:59:29Z
updated_at: 2026-05-19T07:59:29Z
parent: AlaskaRouter-xtua
---

Any landmark visible on the basemap should be tappable — not just our trip waypoints. Cities, gas stations, mountain peaks, lakes, rivers, named features. On tap: open a callout showing name/category/coords, with primary action 'Add to trip'.

Requires either: (a) the basemap tile schema exposes feature ids/attributes we can hit-test (PMTiles vector tiles do — but our current pack is RASTER OpenTopoMap, so no feature data); or (b) we cross-reference tap location against the bundled FTS5 places DB (alaska-places.sqlite) and show the nearest match within a tolerance.

Option (b) is the only path with the current raster basemap. Worth designing before v1 ships.

- [ ] Reverse-geocode tap location -> nearest places-DB row within N px radius
- [ ] Show callout with name + category + 'Add to trip' button
- [ ] Decide how this interacts with waypoint tap (priority order)
