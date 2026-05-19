---
# AlaskaRouter-kcq8
title: Select waypoint by tapping its icon on the map
status: todo
type: feature
priority: high
created_at: 2026-05-19T07:59:23Z
updated_at: 2026-05-19T07:59:23Z
parent: AlaskaRouter-xtua
---

Currently the only way to select a stop is tapping its row in the bottom sheet (RootView.handleSheetWaypointTap). Main UX gap: user can't select directly by tapping the marker on the map. Required for v1.

Depends on getting the selected-icon rendering reliable first (AlaskaRouter-amh7).

- [ ] Wire MLNMapView gesture recognizer (UITapGestureRecognizer) to map tap events
- [ ] Hit-test the tap against rendered waypoint features at the tap location
- [ ] On hit, set selectedWaypointID and animate camera to the waypoint
- [ ] Tap on empty map area = clear selection
- [ ] Verify behavior under panning, zoom, pitch
