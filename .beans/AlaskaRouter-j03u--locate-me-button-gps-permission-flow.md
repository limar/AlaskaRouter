---
# AlaskaRouter-j03u
title: Locate-me button + GPS permission flow
status: completed
type: feature
priority: high
created_at: 2026-05-19T07:16:50Z
updated_at: 2026-05-20T09:39:30Z
parent: AlaskaRouter-xtua
---

MapControls.swift currently has a stubbed-out 'location' button (only shows when onLocateMe closure is non-nil). Need CoreLocation permission request, NSLocationWhenInUseUsageDescription in Info plist, and camera animation to current GPS position. Should also overlay a small pulsing dot at the user's location.



## Summary of Changes

- INFOPLIST_KEY_NSLocationWhenInUseUsageDescription added to project.yml — user-facing prompt text explains map-position use only.
- LocationProvider (new file): MainActor @Observable wrapper around CLLocationManager. Exposes authorizationStatus + lastLocation as reactive properties. requestWhenInUse() triggers the OS prompt; updates auto-start when permission flips to authorized.
- MapControls' onLocateMe stub wired to a new handleLocateMe in RootView. State machine: notDetermined → requestWhenInUse; denied/restricted → no-op (Settings deep-link is a polish follow-up); authorized → start updates and focus camera on the current fix (or wait for first fix, then focus, via .onChange).
- Camera focus preserves the user's current zoom — read via a currentMapZoom() helper that handles all camera-state variants. .center(coord, zoom: cur) — no tracking-mode dance.
- Custom blue puck (WaypointIcons.userLocation): Apple-Maps-style 24pt halo + 14pt blue core with thin white ring + soft outer glow. Pre-rendered UIImage so it's pixel-constant across zooms via iconImage(). Built our own because MapLibreSwiftUI's built-in user-location annotation didn't reliably draw — its showsUserLocation toggle is gated by tracking-mode transitions that fight with manual .center camera changes. Rendering as a SymbolStyleLayer keeps the dot under our control.
- ExpeditionMapView gains a userLocation: CLLocationCoordinate2D? input and a SymbolStyleLayer that draws the puck when it's set.
- LaunchArgs.autoLocateMe + simctl one-liners documented: 'xcrun simctl privacy booted grant location <bundle>' + 'xcrun simctl location booted set <lat>,<lon>' replicate the full flow without manual tapping.

Verified at z=7, z=11, z=14 over Anchorage (simulated): blue puck visible at constant pixel size, camera focused at the requested zoom (no auto-zoom-in).
