---
# AlaskaRouter-2ufd
title: Restore last map view (center + zoom) on app launch
status: completed
type: feature
priority: high
created_at: 2026-05-29T16:59:55Z
updated_at: 2026-05-29T17:10:37Z
---

On launch the map opens at a hardcoded point (RootView mapCamera = .center(63.95,-148.9, zoom 8.5)) far from the user's itinerary, forcing her to pan/zoom to find her route. Persist the last map center + zoom and restore it on next open.

## Design
- The MapLibreSwiftUI camera binding is two-way: on a user gesture the coordinator writes `parent.camera = .center(mapView.centerCoordinate, zoom: mapView.zoomLevel, …)`, so `mapCamera.state` (.centered(onCoordinate:zoom:…)) reflects the live view after each gesture settles.
- Persist center lat/lon + zoom to UserDefaults when the app leaves the foreground (scenePhase → .inactive/.background).
- Restore at view init: seed `mapCamera` from the saved values; fall back to the existing Alaska default when nothing is saved. Skip restore when LaunchArgs.initialZoom is set (keeps screenshot/UI-test launches deterministic).
- Global (app-wide) last view for v1, matching the request. Per-trip memory is a possible follow-up.

## Tasks
- [x] Add scenePhase observation + persistence (UserDefaults keys for lat/lon/zoom)
- [x] Seed initial camera from saved view (guard valid coord + zoom>0; honor LaunchArgs.initialZoom)
- [x] Build (BUILD SUCCEEDED)\n- [x] Verify on simulator (move map, background, relaunch → returns to last view). Confirmed by user.

## Summary of Changes
RootView now persists the map center+zoom to UserDefaults when the app leaves the foreground (scenePhase → .inactive/.background) and seeds the initial camera from it via makeInitialCamera(), falling back to the Alaska default on a fresh install and ignoring the saved view when LaunchArgs.initialZoom is set (deterministic test launches). Confirmed two-way camera binding in MapLibreSwiftUI (coordinator writes centerCoordinate/zoomLevel back after each gesture). Global last-view for v1; per-trip is a possible follow-up. Verified on-device by user.
