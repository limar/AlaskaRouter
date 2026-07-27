---
# AlaskaRouter-xogw
title: Scale label doesn't update during the pinch — only when fingers lift
status: todo
type: bug
priority: high
created_at: 2026-07-27T21:33:50Z
updated_at: 2026-07-27T21:36:47Z
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
