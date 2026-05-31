---
# AlaskaRouter-atvg
title: Search-results panel pushes the search bar off-screen and is itself not scrollable
status: completed
type: bug
priority: high
created_at: 2026-05-23T14:54:58Z
updated_at: 2026-05-31T14:14:11Z
---

## Repro (100 %, iPhone 16)

1. Tap the floating search field — it gets focus, keyboard appears.
2. Type "D" — a long results list renders below the field.
3. The list is tall enough that the *layout* pushes the search field UP, off the top of the screen. The field becomes invisible / unreachable while the keyboard is still up.
4. The results list is itself not scrollable — the only way to interact is to scroll the *whole stack* (which can't because there's no ScrollView wrapping it).

## Observed

- Search bar disappears above the safe-area top.
- User can't see what they typed, can't clear/edit, can't see the close button.
- Result rows are visible but the list can't be scrolled to see entries past the keyboard.

## Expected

- Search field stays *anchored* at the top of the safe area, regardless of how tall the result list is.
- Result list is scrollable (vertical) and clipped to the gap between the field and the keyboard.

## Likely root cause (to verify in code)

The "results dropdown" in `SearchResultsView` is currently a plain `VStack` of `ForEach` rows, with no `ScrollView` wrapper and no explicit max-height. When it's stacked under the search bar in a container that doesn't constrain height (probably a `VStack { FloatingSearchBar; SearchResultsView }` inside the root `ZStack`), the field+results stack overflows the screen and gets pushed up by something — probably an alignment / safe-area interaction with the keyboard.

## Files to inspect

- `AlaskaRouter/UI/FloatingSearchBar.swift`
- `AlaskaRouter/Search/SearchResultsView.swift`
- `AlaskaRouter/App/RootView.swift` (where they're composed)

## Checklist

- [ ] Reproduce on simulator with seeded query "D"
- [ ] Inspect the layout hierarchy — confirm root cause
- [ ] Decide approach (ScrollView wrap, max-height clamp, explicit anchoring)
- [ ] Implement + verify search bar stays put and list scrolls inside its bounds
- [ ] Spot-check at: empty results, 1 result, 20+ results, with/without keyboard visible
