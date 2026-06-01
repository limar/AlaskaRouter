---
# AlaskaRouter-bhs4
title: 'Critical perf: 40-stop trip is unusably laggy when snapped route is present'
status: completed
type: bug
priority: critical
created_at: 2026-06-01T08:14:24Z
updated_at: 2026-06-01T08:22:45Z
---

## Symptom (user report)

Working on iPhone 16 (Release build via Cmd+I) with ~40 waystops in a single Alaska trip. The app becomes unusably sluggish:
- Any tap / pinch / drag has multi-second latency.
- Dragging the bottom sheet is choppy.
- **Typing into the rename-trip alert TextField is laggy** (surprising — text input on the trip name shouldn't touch routing).
- Adding a stop is painfully slow.

The moment routing failed and stops got connected by dashed straight lines (snappedRouteCoords = nil), all lag **disappeared** and the app was fluid again. When routing came back on next launch, lag returned.

Definitive: lag is gated on `snappedRouteCoords` being non-nil.

## Root cause

Two O(W × P) computations recompute on **every** SwiftUI body re-render of the views that touch them. W = waypoints (~40), P = OSRM snapped polyline points (real Alaska routes are several thousand).

1. **`Trip.routeRibbons(snappedCoords:)`** at [Data/TripPasses.swift:80](AlaskaRouter/Data/TripPasses.swift:80)
   - Monotonic waypoint→polyline index mapping: O(W × P) haversines.
   - Sub-leg coverage raster (`cellLegs` dict): rasterizes every polyline edge at half-cell resolution into a Swift `[Int64: Set<Int>]` — for ~5000 polyline edges that's tens of thousands of dictionary inserts and Set allocations.
   - `subRibbons` + `laneMultiplier`: per edge per leg, midpoint + 9 cell lookups + sort.
   - `dissolveShortRuns`: O(n²) per leg, iterates to fixed point.
   - **Called from `ExpeditionMapView.syncTripRouteLayer` inside `.unsafeMapViewControllerModifier`** at [Map/ExpeditionMapView.swift:175](AlaskaRouter/Map/ExpeditionMapView.swift:175) — fires every time the SwiftUI body of ExpeditionMapView re-evaluates.

2. **`Trip.legDistancesMeters(snappedCoords:)`** at [Data/TripDistances.swift:19](AlaskaRouter/Data/TripDistances.swift:19)
   - O(W × P) haversines for the index mapping; O(P) summing per leg.
   - Called from multiple call sites in TripBottomSheet and RootView. Memoization within a render isn't happening — each call site does its own pass.

Call sites we know:
- [App/RootView.swift:836](AlaskaRouter/App/RootView.swift:836) — `legMeters` used twice per StopCallout render (prev + next text).
- [UI/TripBottomSheet.swift:331](AlaskaRouter/UI/TripBottomSheet.swift:331) — `waypointList` per-render.
- [UI/TripBottomSheet.swift:770](AlaskaRouter/UI/TripBottomSheet.swift:770) — `blockSubline` → `blockDistanceMeters` (which itself calls `legDistancesMeters` again).
- [UI/TripBottomSheet.swift:1058](AlaskaRouter/UI/TripBottomSheet.swift:1058) — `distanceText` → `totalDistanceMeters` (which itself calls `legDistancesMeters` again).
- [Map/ExpeditionMapView.swift:175](AlaskaRouter/Map/ExpeditionMapView.swift:175) — `routeRibbons` on every body re-eval of the map.

Typing in the rename alert mutates `renameDraft` @State → TripBottomSheet body re-renders → all three `legDistancesMeters` calls fire → main thread blocks → keystrokes lag. Same mechanism for sheet drag, tap, etc.

## Fix

Memoize at a `TripGeometryCache` (main-actor singleton) keyed on a cheap fingerprint:
- legDistances key: stop lat/lon sequence + snap polyline (count + first/mid/last coords)
- routeRibbons key: above + separator anchor IDs + trip color

Single-slot LRU is enough — once geometry/snap changes, the previous result is stale anyway. Cache hits are free; misses recompute exactly as today.

Update the four+ call sites to go through the cache. No algorithmic change to the routing math itself — that's a bigger lift and not necessary to unblock.

## TODOs

- [x] Add `Data/TripGeometryCache.swift` with `legDistances(for:snappedCoords:)` and `routeRibbons(for:snappedCoords:)` accessors.
- [x] Replace `trip.legDistancesMeters(...)` call at App/RootView.swift:836 with cache.
- [x] Replace three call sites in UI/TripBottomSheet.swift (lines 331, 770, 1058 — total/block/legs) with cache.
- [x] Replace `trip.routeRibbons(...)` at Map/ExpeditionMapView.swift:175 with cache.
- [x] Build (Debug, iOS Simulator) clean. Device smoke-test still pending — user to verify on iPhone 16.
- [x] Added comment block at top of `TripGeometryCache.swift` explaining the bug + invariant.

## Summary of Changes

**New file:** `AlaskaRouter/Data/TripGeometryCache.swift` — `@MainActor` single-slot memoization for `legDistances`, `totalDistance`, `blockDistance`, and `routeRibbons`. Keyed on a cheap fingerprint of stop lat/lon sequence + snap polyline (count + first/mid/last coords) + (for ribbons) separator anchors + trip color.

**Call-site swaps:**
- `App/RootView.swift` — `legMeters` now reads `TripGeometryCache.shared.legDistances(...)`.
- `UI/TripBottomSheet.swift` — `waypointList` legs, `blockSubline`, and `distanceText` all go through the cache.
- `Map/ExpeditionMapView.swift` — `syncTripRouteLayer` marked `@MainActor`; uses `TripGeometryCache.shared.routeRibbons(...)`.

**Effect:** the heavy O(W×P) work runs once per real geometry change. Re-renders triggered by rename-alert typing, sheet drag, taps, and toggles no longer trigger recomputation — typing trip name is no longer ribbon-gated.

**Build:** Debug iOS Simulator build clean. Test suite failure is a pre-existing infra issue (missing gitignored `alaska-pack.pmtiles` for the test runner) — confirmed identical failure on master without these changes.

**Untouched:** the algorithmic structure of `legDistancesMeters` / `routeRibbons` themselves. A future optimization could share the waypoint→polyline index mapping between them and/or reduce the rasterization cost in `routeRibbons`, but with memoization in place the recompute is rare enough that the algorithmic cost is no longer in the interactive critical path.

**Device verification:** user to confirm on iPhone 16 Release build that the 40-stop trip with snapping enabled is now responsive.
