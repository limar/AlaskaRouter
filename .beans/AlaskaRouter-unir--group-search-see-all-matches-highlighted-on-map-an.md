---
# AlaskaRouter-unir
title: Group search — see all matches highlighted on map and pick
status: in-progress
type: feature
priority: normal
created_at: 2026-05-19T07:59:36Z
updated_at: 2026-06-18T04:49:23Z
parent: AlaskaRouter-xtua
---

Search 'campsite' + tap Enter -> all matching campsites in the current view are highlighted on the map. User can pan/zoom and tap any one to preview / add to trip.

Today the search dropdown shows the top N results as a list; user picks one. Group-search is the second mode: see them all in geographic context.

## Resolved design (v1)

Scope: focused-area, single-region (v1 has one bundled alaska-places.sqlite). No "along route" / corridor in v1 — a star/circle trip makes a corridor and "ahead vs behind" ambiguous. Revisit once this UI is solid. (AlaskaRouter-rwbc multi-region is orthogonal.)

Result set = NEAREST N to the current map center, then AUTO-FIT the camera to frame them. (Chosen over strict-viewport so the on-the-road "closest campsite to stay" case still works when the tight viewport is empty.) Center ref = current map center (≈ user location when the map is following). Cap N (~20–30) so the auto-fit frame stays reasonable; very spread-out matches won't zoom the world out. Account for search-bar + collapsed-sheet insets when fitting.

Single vs multiple — intent inferred from the committing gesture:
- Tap a specific suggestion ROW -> SINGLE result (preview that place; becomes the add-candidate). Existing behavior (preview-pin).
- Press Enter / tap the search icon / tap a category CHIP -> MULTIPLE (nearest-N rendered on the map). A chip is inherently plural. Degrades gracefully: a query matching one place = group-of-one.

Query path: add a category-driven, nearest-N path (today runSearch returns top 12 by relevance, first non-empty stage wins). Group mode = category match + distance-from-center sort; skip the loose/fuzzy NAME stages. Infra is fine — 12,617 rows in one immutable SQLite, so scanning + distance sort is sub-ms; no spatial index needed.

Result marker: reuse the existing per-category place-<category> glyphs (PlaceIcons) + a result EMPHASIS treatment (accent ring / halo) so results pop ABOVE (a) the single preview-pin, (b) committed trip stops, and (c) the ambient same-category basemap icons that PlaceIcons already draws. Zoom-scaled, NOT clustered (native MapLibre size interpolation). Min ~44pt tap target even when the glyph is small. Exact emphasis tuned via the existing PlaceIcons Tweaks A/B picker — not a blocker.

Sheet/space: on promote-to-multiple the list sheet COLLAPSES to a thin handle that still shows the count ("27 results"), recoverable by swipe-up/tap (re-expands to a scrollable list of the result set). Search bar persists at top with the active query/chip visible.

Always-editing (we're a Router): showing multiple is a transient browse/pick layer, NOT an edit. Edit happens on tap-a-pin -> preview callout -> add-to-trip, reusing the SAME callout the single path uses. Adding ONE result does NOT clear the others — the result layer persists so the user can add several ("closest campings to stay" = add 2–3).

Lifecycle: one active result-set at a time. A new search replaces the layer; clearing the search bar dismisses it. Chips fade/tuck away on collapse (already in mock, design/mocks/app.jsx ~L449: Fuel · Camp · Visitor · Pass · Lodging · Water). Typed free-text ("McDonalds", "Target") always works as the universal path; chips are shortcuts.

Deferred to tuning stage: along-route/corridor, route-order sort, exact emphasis variant, result cap/dedup at high density, pan-to-"search this area" refresh chip.

- [x] Design UI sketch (spec captured above)
- [x] Consult + get approval
- [x] Implement query-all-results path in SearchService (nearest-N group query)
- [x] Render highlighted-results layer on the map (accent halo + category glyph)
- [x] Tap-highlighted-result -> preview callout (reuses onPlaceTap path)

## Implementation status (slice 1 — compiles, BUILD SUCCEEDED)

Done:
- SearchService.runGroupSearch(near:limit:) + groupResults + clearGroupResults — category/name match, proximity-ranked nearest-N (equirectangular approx), skips fuzzy stages. (Search/SearchService.swift)
- ExpeditionMapView.syncSearchResultLayer — accent-halo MLNCircleStyleLayer + per-category glyph symbol layer; coord-dedup; generic fallback for areal/blank categories; zoom-scaled. New `searchResults` param threaded from RootView. (Map/ExpeditionMapView.swift)
- Result pins are tappable (search-result-icons in allTappableLayerIDs) and carry name/category/admin_area → reuse onPlaceTap → preview → add; adding one keeps the rest. (no new add path needed)
- FloatingSearchBar.onSubmit (Return) → RootView.runGroupSearch; clears query + collapses bar so the dismiss-scrim doesn't eat pin taps; groupResults persists independently.
- Auto-fit: MapViewCamera.boundingBox over the result set (single result → center). (RootView.fitCameraToResults)
- dismissSearch clears groupResults.

SUPERSEDED by later rounds (see below): the marker became a single generic strongly-colored DOT (not halo + per-category glyph) with a live Tweaks color palette; the "count handle" became the single-slot results BADGE.

Still TODO (follow-up slices):
- Far-zoom min-tap-target audit on the result dots.

## Category shortcuts + zero-result handling — done
- Shortcuts (Gas / Camp / Visitor center) live in the search dropdown's EMPTY state as native rows on the same surface as the live suggestions (SearchShortcutsView). Floating-pill version scrapped (melted into the map, collided with the Tweaks button). Tapping a row = category group search.
- Promote ⟺ strict (exact) match count > 0. Never promote optimistically — decided on the async result, so a zero-result commit can't silently close the search.
- Toast "No exact matches for X" fires only when the strict commit finds nothing BUT fuzzy suggestions are visible (the confusing case). Empty dropdown ("kkk") stays silent — the empty list is its own feedback. Fixes the Cancel→Canoe fuzzy corner case.

## Results cleanup UX — resolved (single-slot badge)

One top slot, mutually exclusive — the results badge REPLACES the search bar while a set is on the map (never both, so no ambiguous combos):
- Resting: grey "Search…" pill (trip name removed from the bar — lived there annoyingly).
- Searching: expanded bar + dropdown.
- Results: accent badge "{query} · {count}  ✕", color-matched to the result dots.

Rules:
- ✕ on the badge is the ONLY thing that clears results → returns to the Search… bar. Path to a new search = ✕ then tap the bar.
- Tap badge body → reframe camera to the whole set (explore aid).
- Map gestures / Cancel never clear the set — exploring is stable across all pan/pinch/tap/preview/add.
- A new committed search replaces the set.

Implemented in RootView (resultsBadge, single-slot VStack, groupQueryLabel, clearGroupSearch) + FloatingSearchBar (collapsed pill = "Search…").
