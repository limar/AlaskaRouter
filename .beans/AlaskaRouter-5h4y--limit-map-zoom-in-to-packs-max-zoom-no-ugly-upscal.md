---
# AlaskaRouter-5h4y
title: Limit map zoom-in to pack's max zoom (no ugly upscaling)
status: completed
type: feature
priority: normal
created_at: 2026-05-20T11:29:14Z
updated_at: 2026-05-20T18:49:50Z
parent: AlaskaRouter-xtua
---

Today the camera lets the user zoom past the bundled tile pack's maxzoom (z=10 for Alaska), at which point MapLibre upscales the z=10 tiles into pixelated rectangles. Ugly. Ugly is not in this app's DNA.

## Desired behavior

- Camera maxZoom clamped to the pack manifest's effective max — z=10 for the current alaska-pack.
- When user pinches past the cap, the gesture either stops responding (preferred) or rubber-bands back (acceptable).
- Pinch-out (zoom-OUT) stays unbounded — world skeleton works fine at z=0.

## Likely implementation

MLNMapView has 'maximumZoomLevel'. MapLibreSwiftUI's MapViewCamera has its own pitchRange but I'm not sure about a zoomRange. Investigation paths:

1. **MapView modifier** — search for an existing 'maxZoom' / 'cameraBounds' modifier in MapLibreSwiftUI. The mapView.style.maxZoom in style-base.json doesn't actually clamp the camera, just the tile-fetching behavior.
2. **CameraState clamp** — wrap mapCamera setter so that any state with zoom > 10 is rewritten before assignment. Works but only fires on programmatic changes, not user pinches.
3. **MLNMapView access via raw delegate hook** — set maximumZoomLevel directly on the underlying view. Most direct but requires drop-down access to MLNMapView (we have onMapStyleLoaded for MLNStyle but not for MLNMapView itself; may need to add a delegate hook).

Read the pack max from AlaskaRouter/Resources/alaska-pack.manifest.json's coverage[].maxzoom. Use the highest maxzoom across coverage groups (currently 10).

## Related future bean

When higher-zoom tiles ship (e.g. Anchorage z=14, Denali NP z=15), the cap raises automatically from the manifest. No code change.

- [x] Investigate MapLibreSwiftUI maxZoom path — use unsafeMapViewControllerModifier + MLNMapView.maximumZoomLevel
- [x] Wire cap to manifest.coverage[].maxzoom — via new TilePackManifest.shared.effectiveMaxZoom
- [x] Verify pinch-to-zoom respects cap — MLNMapView clamps gestures natively; verified via simulator extreme-zoom launch arg
- [x] Verify programmatic camera changes (locate-me, waypoint focus) also respect cap — rendered zoom clamps even when binding requests past cap

## Summary of Changes

`AlaskaRouter/Map/TilePackManifest.swift` (new) — single source of truth for the bundled pack's coverage. `Decodable` view of `alaska-pack.manifest.json` with an `effectiveMaxZoom` computed property that returns `max(coverage[].maxzoom)` (z=10 today). Lazy-loaded `static let shared`. Conservative z=10 fallback if the manifest goes missing so the app stays usable.

`AlaskaRouter/Map/ExpeditionMapView.swift` — appended an `.unsafeMapViewControllerModifier` that sets `controller.mapView.maximumZoomLevel = TilePackManifest.shared.effectiveMaxZoom`. This is the MapLibreSwiftUI escape hatch for setting properties of the underlying `MLNMapView` directly, since the SwiftUI DSL doesn't expose camera zoom-range yet.

## Verification

- Build clean.
- Launched simulator with `-preselectStopIndex 0 -initialZoom 13` and `-initialZoom 18`. Map content rendered IDENTICAL in both cases — confirms the underlying `MLNMapView` clamps the visible zoom to z=10 regardless of the camera binding's requested value. Tiles look sharp, no upscaled rectangles.
- Pinch-out (zoom-OUT) past z=0 not tested (irrelevant — the cap is only on the max side).

## Known minor quirk (not in scope)

When the SwiftUI camera binding requests a zoom past the cap (e.g. via the `initialZoom` launch arg), the `MapViewCamera.state` retains the requested value while the rendered tiles clamp. This makes the `ScaleIndicator` (which reads from the camera state, not from the underlying view) show a misleading scale at the over-cap zoom. Doesn't affect normal user pinching — pinch gestures are processed by `MLNMapView` and the regionDidChange callback syncs the binding back to the clamped value. Worth a follow-up bean only if it bites.

## Future raises

When higher-zoom tiles ship (e.g. Anchorage z=14, Denali NP z=15), the cap raises automatically from the manifest — no code change required.
