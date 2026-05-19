---
# AlaskaRouter-any2
title: Search results dropdown aligned to bottom of screen instead of below search bar
status: completed
type: bug
priority: high
created_at: 2026-05-19T07:34:55Z
updated_at: 2026-05-19T09:35:34Z
parent: AlaskaRouter-xtua
---

Type into the search bar -> the single result row appears pinned at the BOTTOM of the screen, just above the safe-area inset, instead of attached directly under the search bar at the top. See user screenshot: query 'Coldfoot Air' yields one result 'Coldfoot Airport' shown ~700px below the search field.

Basic functionality regression — likely a VStack-layout issue in RootView where the results panel is placed after a Spacer instead of immediately under the search bar.

- [x] Reproduce in simulator
- [x] Inspect RootView layout (likely results-panel placement vs Spacer)
- [x] Fix layout: results dropdown should anchor to bottom-of-search-bar
- [x] Verify with screenshot at 1, 3, 7 result rows

## Summary of Changes

The bug was inside FloatingSearchBar.body, not RootView. The bar's own body wrapped its pill in a `VStack { pill; Spacer(minLength: 0) }`. That made the entire view stretch to fill its container's vertical extent — so when RootView placed `[bar, results, Spacer]` in a VStack, the bar consumed almost all the available height and pushed the results dropdown down to the bottom of the screen.

Single-file fix in `AlaskaRouter/UI/FloatingSearchBar.swift`: replaced the inner VStack+Spacer with a plain Group so the bar takes only its intrinsic pill height. The parent VStack now layouts as intended: bar (intrinsic), results (intrinsic, just below), trailing Spacer fills the rest.

Verified with screenshots at empty query, 1 result, and 10+ results — dropdown anchors cleanly under the bar at the top in all three states.
