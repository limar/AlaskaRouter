---
# AlaskaRouter-eai0
title: 'Bug: tap outside search results doesn''t dismiss search'
status: completed
type: bug
priority: high
created_at: 2026-05-24T09:55:56Z
updated_at: 2026-05-29T14:44:00Z
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


## Follow-up: bound ScrollView to content height (2026-05-26)

The original eai0 fix (6e0e888, dim-layer removal + map-tap dismissal) had this caveat:

> A tap inside a tall ScrollView (the search-results panel) but outside any result row may still not dismiss — that's the ScrollView's scroll-gesture territory.

User hit it on device: typing "denali Ai" returns 4 results; tapping below the 4 visible rows (still inside the ScrollView's greedy frame) did nothing, while a slow drag would visibly stretch the panel — confirming the ScrollView was claiming all the empty space.

### Fix

Measure the SearchResultsView's natural content height via a GeometryReader-based `PreferenceKey` (`SearchResultsContentHeightKey`), and bind the ScrollView's frame to `min(measuredHeight, 500)`. Now:

- 4 results → ScrollView is exactly 4-rows tall. Taps below land on the map → `handleMapEmptyTap` → `dismissSearch` (search is active branch).
- 12+ results that overflow 500 pt → ScrollView caps at 500 pt and scrolls internally. Taps below the 500 pt land on the map → dismiss.

### Files

- `AlaskaRouter/App/RootView.swift` — new `private struct SearchResultsContentHeightKey: PreferenceKey`, new `@State searchResultsContentHeight: CGFloat`, new `searchResultsHeightCap: CGFloat = 500`. The ScrollView gains a `.background(GeometryReader { ... preference ... })` on its child, plus `.frame(height: min(measured, cap))` and `.onPreferenceChange`.

The caveat is now closed.


## Regression fix (same day) — replace GeometryReader pattern with `.fixedSize`

The GeometryReader+PreferenceKey approach from 030fa2a hit the chicken-and-egg case: initial `searchResultsContentHeight` is 0, so the ScrollView's frame computed `min(max(0,1), 500) = 1 pt` on first render. The preference round-trip should have caught up on the next layout pass, but SwiftUI's preference propagation didn't complete in time for the conditional-rendered ScrollView, leaving the user with an invisible 1-pt-tall ScrollView and no results.

### Simpler fix

`.fixedSize(horizontal: false, vertical: true).frame(maxHeight: 500)` — one line each, no state, no measurement:
- `.fixedSize(vertical: true)` tells SwiftUI to use the ScrollView's ideal height, which for ScrollView is its content height.
- `.frame(maxHeight: 500)` caps it; when content overflows the cap, the ScrollView scrolls internally.

Removed the `SearchResultsContentHeightKey` PreferenceKey type and the `searchResultsContentHeight` @State var — both dead.


## Second regression (same day) — both attempts to bound the ScrollView misfired

The user hit two distinct layout pathologies with two distinct fixes:

1. **GeometryReader+PreferenceKey (030fa2a)** — initial state was 0 → `min(max(0,1), 500) = 1 pt` ScrollView on first render. No results visible. Preference round-trip didn't catch up.
2. **`.fixedSize(vertical: true)` + `.frame(maxHeight: 500)` (331863e)** — long lists pushed the bar off-screen (the fixedSize'd ScrollView demanded its content height — up to 720+ pt — and the VStack couldn't compress it, so the bar got clipped at top). Short lists rendered with a large gap between the bar and the results card — the VStack appeared to be vertically off-anchored in a way I couldn't fully diagnose under keyboard avoidance.

Both attempts solved the tap-below dismissal but broke the basic layout. Reverting to the simple greedy ScrollView + maxHeight cap restores layout correctness and **accepts the tap-below caveat as a known limitation.**

### Current state (this commit)

```swift
ScrollView { SearchResultsView(...) }
    .frame(maxHeight: 500)
    .scrollDismissesKeyboard(.interactively)
```

The user can dismiss search by:
- Backspacing the query to empty (the results panel disappears once `searchService.results.isEmpty`)
- Tapping the new xmark.circle.fill clear button (7i4o)
- Tapping a result row (preview opens)

### Future work (when we have a time slot)

Cleaner approaches to revisit:
- **Apple's `.searchable`** — native sheet-based dropdown that doesn't have these layout issues. Bigger refactor; would replace the custom FloatingSearchBar visual.
- **GeometryReader with non-zero initial state** — `@State searchResultsContentHeight: CGFloat = searchResultsHeightCap` (initial = cap, then measurement tightens). First render is greedy; brief layout shift to tight on first preference. Might work better than fixedSize.
- **Use a `Group { .. } .layoutPriority(N)` on the bar** to force VStack to give the bar its full height before the ScrollView gets any.
- **Custom layout (Layout protocol, iOS 16+)** — write a 2-child layout that gives bar its intrinsic height and ScrollView the rest, capped.

Reopening eai0 — the tap-below caveat is still officially known and tracked.

## Superseded by AlaskaRouter-y7l0 (2026-05-26)

The ScrollView-bounding approach was abandoned. The new architecture (y7l0):
- Plain VStack with prefix(8) cap → genuinely content-sized, no greedy frame
- Map-touch scrim → any gesture (tap/drag/pinch) dismisses search
- Cancel button replaces AK chip on focus → universal single-tap dismiss

The user's original two failure modes from this bean (tap below short list does nothing; long list covers screen with no map to tap) are both addressed by y7l0. The tap-below-short-list case works because the VStack frame ends at the last row — below is scrim → dismiss. The long-list case is bounded to 8 rows with a "+ N more" hint and a Cancel button always available.

Remaining caveat: NONE in this design. The two ways to dismiss are (1) Cancel button, (2) any touch on visible map.

This bean stays open as the umbrella for the dismiss-on-tap problem, but the active implementation work lives in y7l0.
