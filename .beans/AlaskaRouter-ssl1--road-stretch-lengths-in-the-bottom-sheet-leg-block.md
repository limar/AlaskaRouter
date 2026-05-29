---
# AlaskaRouter-ssl1
title: Road-stretch lengths in the bottom sheet (leg / block / total) + km·mi units toggle
status: completed
type: feature
priority: high
created_at: 2026-05-29T18:55:02Z
updated_at: 2026-05-29T19:34:31Z
---

Surface road-stretch lengths so the user can plan. Distance only this pass (drive time + on-map labels deferred — see follow-ups).

## Design (agreed)
- Per-leg length on each stop row, reusing the slot freed from lat/long: "Town · 23 km" (distance from previous stop, along the road).
- Per-block total on the header subline: "5 stops · 178 km".
- Trip total: upgrade the existing (straight-line) total to ROAD distance when snapped is available; show in summary + stat strip.
- Units: km/mi preference on TweaksStore (toggle in the tweaks panel); all distance displays format through it.
- Road distance from the snapped polyline (per-leg slices); straight-line fallback when unsnapped.

## Tasks
- [x] Trip.legDistancesMeters(snappedCoords:) + total + per-block helpers (testable)
- [x] DistanceFormat (meters → km/mi string) + TweaksStore.distanceUnitIsMiles + TweaksPanel toggle
- [x] Plumb snappedRouteCoords into TripBottomSheet; show per-leg / per-block / total
- [x] Route callout distance strings through the formatter (unit consistency)
- [x] Tests (leg distances, formatter) + build — 32/32 pass\n- [x] Verify on simulator — user confirmed ("significant improvement, bumps usability"). Follow-up: the per-stop distance presentation moves onto a timeline rail (see the mock-alignment epic) to remove from/to ambiguity.

## Summary of Changes
Added road-stretch lengths: Trip.legDistancesMeters/totalDistanceMeters/blockDistanceMeters (snapped polyline, straight-line fallback) + DistanceFormat (km/mi) + a TweaksStore.distanceUnitIsMiles toggle (Tweaks → Units). Bottom sheet shows per-leg length on each stop row, per-block length on headers, and a road-distance trip total; callout distance strings now respect the unit too. Tests 32/32. Drive time + on-map labels deferred (AlaskaRouter-qy0f, -ulf7). Per-stop presentation will move to a timeline rail next.
