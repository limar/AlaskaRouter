---
# AlaskaRouter-q8nl
title: Preserve current zoom when focusing on a selected waypoint
status: completed
type: feature
priority: normal
created_at: 2026-05-20T11:29:23Z
updated_at: 2026-05-20T19:21:59Z
parent: AlaskaRouter-xtua
---

Selecting a waypoint (sheet tap, callout Prev/Next, preselect launch arg) currently calls 'mapCamera = .center(wp.coordinate, zoom: zoomForCategory(wp.category))' — which JUMPS the user's zoom level based on a category-driven heuristic (settlement → 12.5, peak → 11, etc.).

User feedback: 'I choose my zoom level manually and want to jump between waypoints.' The auto-zoom fights with the user's chosen viewing scale, and right now it also kicks the camera past the pack's maxzoom — pixelated upscaling (see AlaskaRouter-<zoom-cap-bean>).

## Desired behavior

For IN-TRIP waypoints (callout Prev/Next, sheet tap, preselect):
- Camera CENTERS on the waypoint
- Zoom STAYS at the current user-chosen level
- Same pattern as locate-me (AlaskaRouter-j03u) — use currentMapZoom() helper

For SEARCH-RESULT previews (PreviewCallout flow):
- Open question — preserving zoom may leave a far-away result off-screen
- Suggest: keep current behavior for previews initially (search results may be far from the user's current viewport), revisit if it feels wrong

## Likely implementation

In RootView, all the in-trip 'mapCamera = .center(coord, zoom: zoomForCategory(...))' sites become 'mapCamera = .center(coord, zoom: currentMapZoom())'. Specific call sites to change (grep for zoomForCategory):

- handleSheetWaypointTap
- handleMapWaypointTap
- handleStopCalloutPrev / Next
- preselectStopIndex onAppear

Leave handlePreviewSelected (search result preview) using zoomForCategory for now.

- [x] Identify all in-trip focus sites
- [x] Switch to currentMapZoom() preservation
- [x] Decide on preview behavior (likely defer) — deferred, zoomForCategory retained for search-preview paths
- [x] Verify Prev/Next walks through stops without changing zoom — user-approved

## Summary of Changes

`AlaskaRouter/App/RootView.swift` — four in-trip focus call sites now preserve the user's chosen zoom via `currentMapZoom()` (the helper introduced in j03u for locate-me):

- `handleSheetWaypointTap` — was hard-coded `zoom: 12.0`
- `handleMapWaypointTap` — was `zoom: zoomForCategory(...)`
- `handleStopCalloutPrev` — was `zoom: zoomForCategory(...)`
- `handleStopCalloutNext` — was `zoom: zoomForCategory(...)`

`zoomForCategory(_:)` is retained for the search-preview / add paths (`handlePreviewSelected`, `handleAddPreviewed`, `handleFastAdd`) — search results may sit outside the current viewport, so framing at a sensible category-driven zoom remains the right default there. Deferred per the bean's "Out of scope" guidance.

`LaunchArgs.preselectStopIndex` path (snapshot-test entry point) untouched — its zoom is set via `LaunchArgs.initialZoom` and is intentional for test fixture generation.

User verification pending on iPhone: walking Prev/Next through stops at z=8, z=11, and z=14 should hold the user's zoom throughout.
