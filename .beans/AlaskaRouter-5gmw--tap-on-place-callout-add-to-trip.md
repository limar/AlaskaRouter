---
# AlaskaRouter-5gmw
title: Tap-on-place callout + add-to-trip
status: todo
type: feature
priority: high
created_at: 2026-05-25T08:42:54Z
updated_at: 2026-05-25T08:42:54Z
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
