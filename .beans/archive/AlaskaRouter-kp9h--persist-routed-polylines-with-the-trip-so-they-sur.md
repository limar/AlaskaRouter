---
# AlaskaRouter-kp9h
title: Persist routed polylines with the trip so they survive offline reopen
status: completed
type: bug
priority: critical
created_at: 2026-05-23T15:20:51Z
updated_at: 2026-05-31T14:18:30Z
---

## Problem

The exact routed polyline (curves following actual roads, returned by ORS while online) is not persisted with the trip. When the user reopens the trip later:

- **Online**: the route is re-fetched and shown correctly as curved roads.
- **Offline**: only the offline spline-fallback is shown — straight dashed lines between waypoints.

This breaks one of our two flagship features (Offline). The whole point of pre-routing while online is to *have* that exact routing available later, **especially** in deep-Alaska no-signal conditions (an "early morning in deep Alaska" reopen is exactly the use case the app was designed for).

## Expected

- The routed geometry computed online is **saved to the trip's SwiftData model**.
- On reopen, the saved routing renders immediately, regardless of network state.
- The straight dashed-line fallback only appears for legs that were *never* successfully routed online (e.g. brand-new stops added while offline) — and those legs auto-upgrade to real routing when connectivity returns (existing `pendingSnap` machinery).

## Scope

- **In scope**: persist the snapped route geometry (per-leg or per-trip) in SwiftData; load and render it on trip open; preserve the existing `pendingSnap`/auto-refresh-on-reconnection flow for new edits.
- **Out of scope**: re-routing freshness (re-fetching when ORS data has changed) — that's a separate concern; for v1 a saved route is "good enough" until the user explicitly refreshes.

## Files to inspect

- `AlaskaRouter/Routing/RoutingProvider.swift`
- `AlaskaRouter/Data/TripModels.swift` (SwiftData schema)
- `AlaskaRouter/Data/TripSegments.swift`
- `AlaskaRouter/Data/TripPasses.swift`
- `AlaskaRouter/Routing/NetworkMonitor.swift`
- `AlaskaRouter/App/RootView.swift` (where snappedRouteCoords is wired)

## Checklist

- [x] Audit current routing pipeline + persistence boundary
- [x] Decide storage shape — trip-level JSON blob on Trip (encoded `[[lat,lon],…]`). Matches the architecture: `passOffsetSegments`, `routeRibbons`, `blockGeometries` all consume a single trip-level polyline today, so persisting at the same granularity is the smallest change.
- [x] SwiftData schema migration — additive: three optional fields on `Trip` (`snappedRouteEncoded: String?`, `snappedRouteKey: String?`, `snappedRouteComputedAt: Date?`). Existing trips load with nil cache → fresh fetch on next open → cache filled on success.
- [x] Save snapped geometry when ORS returns — `runSnap` now calls `trip.setSnappedCoords(...)` + `modelContext.save()` after a successful ORS call. Guards against trip-switch / edit-during-flight by re-checking `tripGeometryKey == key` before persisting.
- [x] Load and render on trip open — `scheduleSnapForCurrentTrip` checks `trip.cachedSnappedCoords(for: tripGeometryKey)` FIRST. On cache hit it hydrates `snappedRouteCoords` immediately and returns, skipping the network call entirely. Cache key mismatch (after waypoint edit) falls through to the normal fetch path.
- [ ] Verify offline reopen shows routed paths (on-device test)
- [ ] Verify online-edit re-saves new legs (on-device test)
- [ ] Verify `pendingSnap` flow still triggers for unrouted legs (on-device test)
