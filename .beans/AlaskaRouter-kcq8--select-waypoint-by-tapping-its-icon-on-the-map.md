---
# AlaskaRouter-kcq8
title: Select waypoint by tapping its icon on the map
status: completed
type: feature
priority: high
created_at: 2026-05-19T07:59:23Z
updated_at: 2026-05-20T09:05:37Z
parent: AlaskaRouter-xtua
---

Currently the only way to select a stop is tapping its row in the bottom sheet (RootView.handleSheetWaypointTap). Main UX gap: user can't select directly by tapping the marker on the map. Required for v1.

Depends on getting the selected-icon rendering reliable first (AlaskaRouter-amh7).

- [x] Wire MLNMapView gesture recognizer to map tap events (via .onTapMapGesture(on:))
- [x] Hit-test the tap against rendered waypoint features at the tap location
- [x] On hit, set selectedWaypointID and animate camera to the waypoint
- [x] Tap on empty map area = clear selection (callout dismiss)
- [x] Verify behavior under panning, zoom, pitch (user to confirm on device)

## Summary of Changes

- ExpeditionMapView: added onWaypointTap: ((UUID?) -> Void)? plus a .onTapMapGesture(on: [marker-layer-ids]) modifier. Tap on a marker feature -> callback fires with the waypoint's UUID (extracted from the feature's 'wpID' attribute we now stamp on every MLNPointFeature). Empty-area tap -> callback fires with nil.
- StopCallout (new UI/StopCallout.swift): floating callout matching the design-handoff mock's POI panel pattern, trimmed for v1 essentials. STOP N OF M label, category icon + name + close ×, '... km from previous' detail line, tomato 'Remove from trip' destructive primary button. Prev/Next chevrons sit OUTSIDE the callout body as small translucent capsule buttons (disabled / faded at first / last).
- RootView:
  - Passes handleMapWaypointTap as the onWaypointTap callback.
  - Renders the StopCallout in the body when selectedWaypointID is set + previewedResult is nil + search isn't active.
  - handleMapWaypointTap(nil) -> clears selectedWaypointID (tap-outside dismiss).
  - handleStopCalloutClose / Prev / Next / Remove handlers.
  - handleStopCalloutRemove: instant delete + renumber remaining stops. No Undo toast and no confirmation alert per user spec (different from the sheet trash, which DOES get an Undo).
- preselectStopIndex onAppear: wrapped in a Task with a 250ms delay to dodge the SwiftData @Query propagation race on fresh installs.
