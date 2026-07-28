---
# AlaskaRouter-35z7
title: Search-result dots are nearly untappable — nearby POIs win the hit-test
status: completed
type: bug
priority: high
created_at: 2026-07-27T22:40:00Z
updated_at: 2026-07-28T00:52:13Z
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
- [x] Add the search-result priority tier to the dispatch
- [x] Enlarge the effective touch target — invisible hit layer, 22 pt radius
- [x] Verified: 24-result group search, tapped without zooming in

## Summary of Changes

Both causes fixed.

**1. Priority tier.** Result features now carry an `isSearchResult` attribute, and `dispatchKnownObject` gained a tier for them between trip waypoints and ambient places. Previously both kinds of feature carried only `name` + `category`, so the winner was whichever the hit-test happened to return first — and in the field a nearby POI almost always stole the tap.

**2. Hit target separated from the drawn mark.** A fully transparent `search-result-hit` circle layer (22 pt radius ≈ a 44 pt touch target) is added *under* the visible dot and included in the tappable layer set. The visible dot keeps its 4.5–11 pt zoom-scaled size, so a result set still reads as a density cloud rather than a wall of pins — the mark and the target no longer have to be the same size.

Worth noting: `circleOpacity = 0` does **not** exclude a layer from `visibleFeatures(at:styleLayerIdentifiers:)`, so no visible-but-faint fudge was needed. Verified empirically rather than assumed.

**Verified on a 24-result "campground" group search around Fairbanks:**
- Tapping **12 px off** a dot's centre still selected it ("Upper Chatanika State Rec…") — that miss distance would previously have failed.
- Tapping inside the dense Fairbanks label cluster, where Chena / Fairbanks / Chickaloon POIs compete, selected the result ("Moose Loop RV Campgro…") rather than a POI.

Neither test needed any zooming in, which was the field workaround.
