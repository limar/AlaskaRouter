---
# AlaskaRouter-eai0
title: 'Bug: tap outside search results doesn''t dismiss search'
status: in-progress
type: bug
priority: high
created_at: 2026-05-24T09:55:56Z
updated_at: 2026-05-24T10:03:32Z
parent: AlaskaRouter-ka6b
---

## Repro (iPhone 16)

1. Tap floating search field.
2. Type a letter — results dropdown appears.
3. Tap the map area BELOW the dropdown — expectation: search dismisses (keyboard down, dropdown gone, map gets the tap).
4. Actual: nothing happens. Search stays open. Tap doesn't reach the map.

## Likely cause

RootView has a transparent \`Color.black.opacity(0.001)\` dim layer behind the search-active state that's supposed to catch dismissal taps. But the new \`ScrollView { SearchResultsView }\` we added in atvg may be sitting on top with \`.contentShape(Rectangle())\` style hit-testing that intercepts events even in its empty (scroll-padding) areas.

OR the VStack containing bar + ScrollView is sized to fill the whole map area when there are results, swallowing taps that should reach the dim layer.

## Likely related to:

The \"map ungesture-able when search bar focused\" bug — same root cause probably.

## Investigation steps

- [ ] Check what view hierarchy ends up between the user's tap and the dim-layer
- [ ] Confirm dim layer is reachable when search is active
- [ ] Confirm map gesture priority order
- [ ] Fix + on-device verify both this and the related map-gesture bug close


## Fix applied (2026-05-24)

Same root cause as `AlaskaRouter-l556` — the transparent dim-layer overlay captured all gestures including taps that should have dismissed search. Fix is the same: removed the dim-layer, route dismiss-on-tap through `handleMapWaypointTap` which fires from the map's native single-tap recognizer.

Caveat: a tap **inside** a tall ScrollView (the search-results panel) but outside any result row may still not dismiss — that's the ScrollView's scroll-gesture territory. Tap below the ScrollView (in the Spacer area) → falls through to map → dismisses search. The "below the panel" case is the user's primary one and should now work.

- [x] Confirm dim layer is the source of tap-capture
- [x] Remove dim layer
- [x] Route dismiss via map tap recognizer
- [ ] On-device verify
