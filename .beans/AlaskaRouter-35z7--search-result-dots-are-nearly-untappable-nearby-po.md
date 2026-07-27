---
# AlaskaRouter-35z7
title: Search-result dots are nearly untappable — nearby POIs win the hit-test
status: todo
type: bug
priority: high
created_at: 2026-07-27T22:40:00Z
updated_at: 2026-07-27T22:40:00Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. Selecting a group-search result required zooming to maximum and tapping very precisely, and even then a nearby POI or city usually caught the tap instead.

## Two distinct causes

**1. No priority in the dispatch.** `ExpeditionMapView.dispatchKnownObject` picks a place with:
```swift
features.first(where: { $0.attribute(forKey: "name") != nil && $0.attribute(forKey: "category") != nil })
```
Search-result features carry **exactly those two attributes** (`syncSearchResultLayer` sets `name` / `category` / `admin_area` so a result tap can reuse the preview→add flow). So do the `places-tier-*` features. The hit-test returns both in unspecified order and whichever lands first wins — there is nothing expressing "the user just searched for these, they win".

Fix direction: give the result features a distinguishing attribute (e.g. `isSearchResult`) in `syncSearchResultLayer` and add an explicit tier to the dispatch, between trip waypoints and ambient places.

**2. The target is genuinely tiny.** `searchResultDotStops` is 4.5 pt radius at z6, 7 at z9, 11 at z12 — well under the ~44 pt comfortable touch target, and the user was trying to hit them on a moving vehicle. Ambient POI icons are larger and so are easier to hit even when the intended target is closer to the finger.

Fix direction: a transparent, larger hit circle layer under the visible dot (common MapLibre trick), or simply a bigger marker — which the sibling bean about the puck collision may want anyway.

## Todo
- [ ] Add the search-result priority tier to the dispatch
- [ ] Enlarge the effective touch target (invisible hit layer vs bigger marker — decide with the visual round)
- [ ] Verify: run a group search in a dense area, tap results without zooming in
