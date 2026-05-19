---
# AlaskaRouter-j03u
title: Locate-me button + GPS permission flow
status: todo
type: feature
priority: high
created_at: 2026-05-19T07:16:50Z
updated_at: 2026-05-19T07:16:50Z
parent: AlaskaRouter-xtua
---

MapControls.swift currently has a stubbed-out 'location' button (only shows when onLocateMe closure is non-nil). Need CoreLocation permission request, NSLocationWhenInUseUsageDescription in Info plist, and camera animation to current GPS position. Should also overlay a small pulsing dot at the user's location.
