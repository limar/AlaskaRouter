---
# AlaskaRouter-y7l0
title: Cancel button design spike + map-touch scrim + count-capped dropdown
status: in-progress
type: feature
priority: high
created_at: 2026-05-26T15:55:52Z
updated_at: 2026-05-26T16:14:25Z
parent: AlaskaRouter-ka6b
---

Composite fix for the search dropdown UX. Replaces the failed ScrollView-bounding work (eai0 round 2-3) with three coordinated pieces that respect the user's locked UX spec.

Sibling of `AlaskaRouter-eai0` under the `ka6b` UI polish epic.

## Pieces

### 1. Cancel button replaces AK chip on focus
- `FloatingSearchBar` swaps the orange AK chip for a Cancel button when `fieldFocused == true`. AK comes back on blur.
- Cancel is a labeled text/chip (NEVER an icon — avoids the two-x antipattern user warned about).
- New `onCancel: () -> Void` callback parameter wired to `RootView.dismissSearch()`.

### 2. TweaksStore design knobs for Cancel
Spike harness pattern (like vyfe `placeMarkerStyle`) — user A/Bs on-device, we lock the winner, then strip tweaks.
- `cancelButtonStyle: Int` — 0=plain text, 1=filled chip, 2=outlined chip
- `cancelButtonColor: Int` — 6-color curated palette (slate blue / brand blue / system blue / charcoal / gray / teal)
- `cancelButtonFontWeight: Int` — 0..4 → regular/medium/semibold/bold/heavy

### 3. Dropdown: VStack with count cap (drop ScrollView)
- Render `results.prefix(8)` as a plain VStack — no ScrollView, no greedy frame.
- "+ N more results — refine your query" footer when count > 8.
- Frame is naturally content-sized → tap-below the rows lands on map → triggers dismiss.

### 4. Map-touch scrim — all gestures dismiss
- Transparent overlay sits between map and bar/results when `isSearchActive`.
- `DragGesture(minimumDistance: 0)` catches any touch-down (tap/drag/pinch all start there) → `dismissSearch()`.
- Restores pre-eai0 "tap-outside-dismiss" but for ALL gestures, per user's explicit spec: "Any touch on map (tap, drag, pinch, whatever) should just dismiss the search sheet without doing anything else."

## Todo

- [x] Add cancelButtonStyle / cancelButtonColor / cancelButtonFontWeight to TweaksStore
- [x] Add Search-bar section to TweaksPanel
- [x] Add Cancel button rendering to FloatingSearchBar (3 style variants × 6 colors × 5 weights)
- [x] Wire onCancel callback from FloatingSearchBar to RootView.dismissSearch
- [x] Add overflowCount: Int parameter to SearchResultsView + "+ N more" footer
- [x] Replace ScrollView in RootView with VStack-with-prefix(8)
- [x] Remove searchResultsHeightCap constant
- [x] Add scrim layer in RootView between map and bar
- [ ] Build & verify on device
- [ ] Lock the winning style/color/weight combo; strip tweaks (separate follow-up bean)

## Files touched

- AlaskaRouter/UI/TweaksStore.swift
- AlaskaRouter/UI/TweaksPanel.swift
- AlaskaRouter/UI/FloatingSearchBar.swift
- AlaskaRouter/Search/SearchResultsView.swift
- AlaskaRouter/App/RootView.swift

## Status (2026-05-26 sim build)

All code wired, builds cleanly for iPhone 17 simulator. On-device verification still pending. The Tweaks panel now has a Search-bar Cancel-button section with style × color × weight pickers — flip them on device, land on a combo, then the strip-tweaks follow-up bean removes the harness.

## Revert: count cap + footer removed (2026-05-26)

User pushed back on the displayedResultsCap = 8 + "+ N more" footer — "incomprehensible, counterintuitive and shows too few search results." Fair: the cap was a defense against a bar-push failure mode that was actually caused by `.fixedSize`, not by an unbounded ScrollView. ab23a70's plain ScrollView never had that problem.

Restored ab23a70's layout: a ScrollView with `.scrollDismissesKeyboard(.interactively)` and no cap. All results shown; scrolls internally if overflowing. Dismissal stays clean because Cancel button is always available and the map-touch scrim catches gestures on visible map.

- SearchResultsView: removed `overflowCount` parameter and the footer block
- RootView: dropped `displayedResultsCap` constant, replaced VStack-with-prefix with the ScrollView wrapper

The eaten-tap-inside-ScrollView edge case is now non-fatal — Cancel handles it.
