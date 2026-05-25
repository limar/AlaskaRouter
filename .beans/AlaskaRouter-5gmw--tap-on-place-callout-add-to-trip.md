---
# AlaskaRouter-5gmw
title: Tap-on-place callout + add-to-trip
status: in-progress
type: feature
priority: high
created_at: 2026-05-25T08:42:54Z
updated_at: 2026-05-25T19:16:07Z
parent: AlaskaRouter-0z7e
---

## Scope (child of AlaskaRouter-0z7e)

Tapping a non-trip place marker (rendered by the sibling place-markers bean) opens a callout showing the place's name + category + admin_area, with a primary "+ Add to trip" capsule.

## Design

- Reuse `PreviewCallout` (already used for the search-result preview flow) or extract a sibling `PlacePreviewCallout`. Same look and feel.
- Show: name (serif), category (small caps), admin_area ("Denali, AK, USA"), "+ Add to trip" capsule.
- On "+" → existing `SmartInsert.insertSmart` flow, then the same post-add behavior as search-result add (`gxv0`'s fast-add: keep map focus, no toast, no auto-select).

## Tap dispatch

In `ExpeditionMapView.onTapMapGesture(on: layerIDs)`, the union of trip-waypoint layers + place-marker layers is queried. Iteration priority:

1. Trip-waypoint hit → existing `StopCallout` flow
2. Place-marker hit → new `PlacePreviewCallout`
3. Empty area → new `MapDropPinCallout` (separate bean)

## Checklist

- [ ] Decide PreviewCallout reuse vs PlacePreviewCallout split
- [ ] Wire tap → callout via shared `previewedResult`-style state in RootView
- [ ] "+" → SmartInsert (parity with search-result add)
- [ ] On-device verify


## Summary of Changes

Wired the map's single-tap recognizer to dispatch place taps in addition to the existing trip-waypoint and empty-area cases. The user can now tap a city, peak, fuel station, viewpoint — anything in `places.geojson` — and get a callout with name + admin area + "+ Add to trip" capsule.

### Implementation

**`ExpeditionMapView.swift`**
- New value type `MapPlaceTap` (top-level so RootView can store it without bringing the whole map-view into the import). Carries `name`, `category`, `coord`, `adminArea` — the minimum the callout needs.
- New callback `var onPlaceTap: ((MapPlaceTap) -> Void)?`.
- New static set `placesLayerIDs` listing all `places-tier-*` symbol layer IDs (major-settlement / settlement / peak / natural-major / misc / long-tail). Combined with `waypointLayerIDs` into `allTappableLayerIDs`.
- The single `.onTapMapGesture(on: allTappableLayerIDs)` handler now dispatches by priority:
  1. **Trip waypoint** (any feature with `wpID` attribute) → `onWaypointTap(uuid)`
  2. **Place feature** (any feature with `name` + `category`) → `onPlaceTap(MapPlaceTap)`
  3. **Empty area** → `onWaypointTap(nil)`
- Trip waypoints win when stacked because the user's own data should take precedence.

**`RootView.swift`**
- New `handleMapPlaceTap(_:)` synthesizes a `SearchResult` from the `MapPlaceTap` (deterministic `id` via Hasher so SwiftUI diffs cleanly across consecutive taps) and assigns it to `previewedResult`. The existing `PreviewCallout` view renders, and "+ Add to trip" routes through the existing `handleAddPreviewed` → `SmartInsert.insertSmart` path — same flow as adding from a search result.
- Empty-area tap also clears `previewedResult` (so tapping the empty map dismisses an open place preview).
- Tapping a place clears `selectedWaypointID` (no double-callout — StopCallout for trip waypoints + PreviewCallout for tapped place would compete).

### Why reuse `PreviewCallout`

`PreviewCallout` was built for the search-result preview flow. The shape is identical to what we need for a map-tapped place: a sheet showing name, category, admin area, distance from trip, with a "+ Add to trip" capsule. Reusing it avoids duplicating layout + halo/material/dismiss plumbing. The `SearchResult` type is the de-facto "thing the user might want to add to a trip" — synthesizing one for map taps unifies the data flow.

### Checklist

- [x] `MapPlaceTap` value type
- [x] `onPlaceTap` callback wired into `onTapMapGesture`
- [x] Tap dispatch: waypoint > place > empty
- [x] `handleMapPlaceTap` synthesizes a `SearchResult` and routes through `PreviewCallout`
- [x] Empty-area tap also clears `previewedResult`
- [x] Place tap clears `selectedWaypointID` (single-callout invariant)
- [ ] On-device verify: tap a peak, fuel station, settlement — callout shows, "+" adds the place
