---
# AlaskaRouter-8w9l
title: Search-result dots look identical to the My Location puck
status: todo
type: bug
priority: high
created_at: 2026-07-27T22:40:00Z
updated_at: 2026-07-27T22:40:00Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. The group-search result markers read as the same object as the user's own GPS position — both are blue discs with a white ring.

## Cause — it is the same colour, by default
- `SearchResultStyle.swift:14` — "Index 0 is the default (a vivid electric blue…)", and `TweaksStore.swift:261` sets `searchResultColor = 0`.
- `WaypointIcons.makeUserLocation()` (`WaypointIcons.swift:157`) draws the puck in `rgb(0.10, 0.45, 0.95)` — the same blue family — with a white ring and a soft halo.
- `ExpeditionMapView.syncSearchResultLayer` draws each result as an `MLNCircleStyleLayer`: coloured disc + 2 pt white stroke. Same shape, same colour, same size range.

The two are deliberately *generic* for different reasons — the search set wants to read as one homogeneous "your matches" layer (AlaskaRouter-unir), the puck wants to read as "you" — and they collided.

## Options to discuss
- Recolour one of them. Cheapest, but blue-for-me is a strong convention worth keeping, so the search set should move — and it has a whole curated palette already (`SearchResultStyle`).
- Change the *shape* rather than the colour: a teardrop/pin silhouette for results vs a disc for the puck. Shape survives colour-blindness and small sizes better than hue.
- Give the puck its directional/halo treatment more prominently so "you" is unmistakable regardless of what else is on the map.

Related: AlaskaRouter-xyz1 below — the same markers are also nearly untappable, and a bigger/different marker may fix both at once. Worth designing the two together.

## Todo
- [ ] Decide the visual language (shape vs colour) — rendered variants over the real map, light + dark
- [ ] Implement
- [ ] Verify against the puck on screen at the same time, at several zooms
