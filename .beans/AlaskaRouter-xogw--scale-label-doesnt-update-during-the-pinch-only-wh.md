---
# AlaskaRouter-xogw
title: Scale label doesn't update during the pinch — only when fingers lift
status: in-progress
type: bug
priority: high
created_at: 2026-07-27T21:33:50Z
updated_at: 2026-07-27T21:58:52Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. The scale label only refreshes when the zoom gesture *ends*, so you cannot pinch to a target scale — you zoom blind, release, read, adjust, repeat.

## Cause — already solved upstream, we just aren't using it
`RootView.swift:269` feeds `ScaleIndicator(camera: mapCamera)`. The `MapViewCamera` binding is written back by MapLibreSwiftUI's coordinator only on region-*did*-change.

MapLibreSwiftUI exposes exactly the knob we need:
- `MapViewCoordinator.swift:534` — `regionIsChangingWith` fires continuously, but only forwards the proxy `if proxyUpdateMode == .realtime`
- default is `.onFinish` (`MapView.swift:71`) — that is what we're getting
- `ViewModifiers/OnMapProxyUpdate.swift:64` — `.onMapViewProxyUpdate(updateMode:)` sets the mode and delivers a live `MapViewProxy`

So: opt into `.realtime` and drive `ScaleIndicator` off the live `MapViewProxy` (center + zoom) instead of the `camera` binding.

## Watch out
- `.realtime` fires on every frame of every pan, not just zoom. The scale math is cheap, but re-rendering the whole `RootView` body per frame is not — the proxy must land in narrow state that only `ScaleIndicator` observes, or a 54-stop trip will stutter (cf. AlaskaRouter-bhs4).
- The label recomputing every frame will also *flicker* between ladder steps. Consider only re-rendering when the chosen step actually changes.

## Todo
- [ ] Wire `.onMapViewProxyUpdate(updateMode: .realtime)`; scope the state so only the scale re-renders
- [ ] Profile a pan/pinch on the 54-stop Alaska trip — no regression vs today
- [ ] Verify on device: label tracks the fingers continuously

## Progress — implemented, awaiting device confirmation

**Done.** `ScaleIndicator` no longer reads the `MapViewCamera` binding at all. A small `@Observable MapScaleReading` carries `metersPerPixel`, fed from `.onMapViewProxyUpdate(updateMode: .realtime)` on the map in RootView.

The perf worry in the bean is handled by construction: RootView holds the object but **never reads `metersPerPixel` in its own body**, so a realtime update invalidates only `ScaleIndicator`, not RootView-with-a-54-stop-trip. `MapScaleReading.update` also drops writes that don't change the value (a pure horizontal pan doesn't change resolution, and Observation notifies on every set regardless of equality).

**Verified:** the bar renders and reports correct values — and since `metersPerPixel` now comes *only* from the realtime proxy (zero → renders nothing), the proxy path is provably live.

**NOT verified: that it tracks a finger continuously.** That distinction lives entirely in `.realtime` gating `regionIsChangingWith` (source-read in MapViewCoordinator.swift:534), and I could not exercise it on the Simulator:
- there is no input injection available for a pinch (the Xcode simulator MCP is blocked by an `xcode-select` config issue needing sudo);
- the app's own camera moves turned out to be poor substitutes — `handlePreviewSelected` deliberately *preserves* zoom (AlaskaRouter-q8nl), and the launch-time camera arrives as a single jump.

A 14 s screen recording of an app-driven camera flight was captured and frame-stepped at 0.05 s; it confirms the label updates and changes, but the only zoom transitions available were instantaneous, so it cannot distinguish `.realtime` from `.onFinish`.

## Todo
- [ ] Confirm on the physical device: pinch slowly, label must move continuously rather than snapping on release
- [ ] Watch for step flicker while pinching across a ladder boundary — if it's distracting, damp it
