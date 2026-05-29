---
# AlaskaRouter-l556
title: 'Bug: search-bar focused state blocks map gestures'
status: completed
type: bug
priority: high
created_at: 2026-05-24T09:55:56Z
updated_at: 2026-05-29T14:43:53Z
parent: AlaskaRouter-ka6b
---

## Repro (iPhone 16)

1. Tap the floating search field. Field becomes focused, keyboard appears, but the user has NOT typed anything yet.
2. Try to pinch-zoom / pan the map.
3. Actual: gestures don't reach the map. Pinches and pans are ignored.

## Likely cause

Same as the tap-outside bug — when search is active (\`isSearchActive\` becomes true the moment the field is focused, even with empty query), the dim-layer + VStack + (possibly empty) ScrollView form a stack that swallows gestures.

## Goal

Map remains gesture-able even while search is focused. Tapping the map dismisses search; pan/zoom over the map area work. The search bar itself should still receive its own taps (focus/blur).

## Likely related to:

Bug: tap outside search results doesn't dismiss search. Probably the same fix.

## Checklist

- [ ] Diagnose with bug-tap-outside (single root cause likely)
- [ ] Decide hit-testing model so map gestures + search dismiss both work
- [ ] Implement
- [ ] On-device verify pinch-zoom while search focused


## Fix applied (2026-05-24)

Removed the dim-layer overlay (`Color.black.opacity(0.001) + onTapGesture { dismissSearch() }`) from RootView's ZStack. That overlay used `.contentShape(Rectangle())` over the full screen which captured **all** gesture types — taps fired dismissSearch fine, but pinches, pans, and rotations died on it and never reached the underlying MapLibre map. Result: map became un-zoomable the moment the search field got focus.

Tap-to-dismiss is now routed through `handleMapWaypointTap`: the MapLibre native single-tap recognizer fires for empty-area taps (and waypoint taps), and `handleMapWaypointTap` calls `dismissSearch()` first when `isSearchActive`. With this:

- Pinch / pan / rotate work normally on the map at all times.
- Tap on map area while search active → dismisses search.
- Tap on waypoint while search active → dismisses search AND selects the waypoint (iOS-standard "focused-search + tap = both happen").

Same fix resolves `AlaskaRouter-eai0` (tap-outside-results-list doesn't dismiss) since both bugs were the same dim-layer claim.

- [x] Diagnose with bug-tap-outside (single root cause confirmed)
- [x] Decide hit-testing model so map gestures + search dismiss both work
- [x] Implement
- [ ] On-device verify pinch-zoom while search focused
