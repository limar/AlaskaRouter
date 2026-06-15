---
# AlaskaRouter-th0e
title: 'Bug: search bar won''t collapse + Cancel vanishes after Enter/scroll (focus-gated affordance)'
status: completed
type: bug
priority: high
created_at: 2026-06-15T08:40:11Z
updated_at: 2026-06-15T09:03:25Z
---

Two related regressions in the FloatingSearchBar collapse/expand + dismiss affordance.

ROOT CAUSE (single): the y7l0 spike (commit cdfded8) gated the Cancel button on the keyboard-focus state (`if fieldFocused`) instead of on whether search is active. The trailing chip swaps: focused -> Cancel, blurred -> decorative AK chip. The collapse path (dismissSearch -> barState=.collapsed) is only reachable via the Cancel button or the map scrim.

Bug 2 (the corner case): type 'visitor' -> results -> tap Return (submitLabel .search). The keyboard dismisses, blurring the field, but the query/results remain. Cancel reverts to the decorative AK chip -> dismiss affordance gone. Same thing happens when scrolling the results list (scrollDismissesKeyboard(.interactively) blurs the field).

Bug 1 ("doesn't collapse anymore"): generalization of the above. Once focus is lost while a query/results remain, Cancel is gone and the only collapse path left is the map scrim, which is largely occluded by the results list -> bar feels permanently stuck expanded.

FIX DIRECTION: tie the Cancel/dismiss affordance to 'search is active' (focused OR non-empty query), not to keyboard focus. Define one rule-set for expand/collapse and Cancel visibility. Extract the decision into a pure, testable helper and add a unit test.

- [x] Confirm + document the exact expand/collapse + Cancel-visibility rule-set
- [x] Get UI sign-off on the rule-set (AK chip fate) — user chose: retire the AK chip
- [x] Implement: drive Cancel + barState from search-active, not fieldFocused
- [x] Extract pure decision helper (SearchBarRule) + add unit test (9 cases)
- [x] Verify in the failure surface (prefill=blurred+query shows Cancel; plain launch rests collapsed)

## Summary of Changes

**Rule-set (single source of truth):** search is *active* when the field is focused OR the query is non-empty. The bar is expanded while active, collapsed otherwise; Cancel is shown whenever the bar is expanded (never focus-gated).

- `SearchBarRule` (new, FloatingSearchBar.swift) — pure helpers `isSearchActive`, `restingState`, `showsCancel`. Unit-tested (`SearchBarRuleTests`, 9 cases in Tests/SearchTests.swift).
- `FloatingSearchBar` — trailing slot is now always Cancel; retired the decorative AK chip (it only appeared in the broken blurred-but-active state and stole the dismiss affordance).
- `RootView` — `isSearchActive` routes through `SearchBarRule`; new `.onChange(of: isSearchActive)` -> `syncBarState` keeps collapse/expand in lockstep across every blur path (Return, interactive results-scroll, preview-tap). Eager pill-tap expand preserved.
- `LaunchArgs.initialBarState` — runtime default flipped expanded -> collapsed (map-mode resting state); screenshot `-barState`/`-prefillQuery` overrides still work.

**Verified:** all 107 tests pass; in-simulator, a query-present/blurred launch shows Cancel (was the AK chip), and a plain launch rests on the collapsed trip-name pill (was expanded).
