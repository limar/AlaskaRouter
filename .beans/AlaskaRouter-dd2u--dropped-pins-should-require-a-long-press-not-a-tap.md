---
# AlaskaRouter-dd2u
title: Dropped pins should require a long press, not a tap
status: completed
type: bug
priority: high
created_at: 2026-07-27T21:32:58Z
updated_at: 2026-07-27T22:13:24Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. While exploring/panning the map, incidental touches register as taps and pop the "Dropped Pin" callout. Noise.

## Desired behaviour (Google Maps grammar)
- **Tap** on a *known object* (trip waypoint, POI, place marker) → its callout. Unchanged.
- **Tap** on *empty map* → dismiss whatever callout is open. Nothing else. No pin.
- **Long press** on empty map → drop a pin + callout (+ haptic).

## Where it lives
`AlaskaRouter/Map/ExpeditionMapView.swift:621` — `.onTapMapGesture(on: allTappableLayerIDs)` dispatches:
1. trip waypoint → `onWaypointTap`
2. place feature → `onPlaceTap`
3. **empty → `onEmptyMapTap(context.coordinate)`** ← this branch is the offender

MapLibreSwiftUI already ships `.onLongPressMapGesture` (`ViewModifiers/OnMapGestures.swift:138`), so the move is: branch 3 becomes "dismiss only", and a new long-press modifier calls the drop-pin path. Both `onEmptyMapTap` callers live in `App/RootView.swift` (~1280, ~1322).

## Open UI questions (decide before implementing)
- [x] Long-press duration — system default (0.5 s), the DSL modifier default
- [x] Haptic on pin drop — yes, UIImpactFeedbackGenerator(style: .medium) on drop
- [x] Empty tap clears BOTH callout and selection in one go — agreed with the user
- [x] Known object wins on long press too — agreed with the user

## Todo
- [x] Agree the behaviour table above
- [x] Implement: tap-empty → dismiss; long-press-empty → drop pin
- [x] Verify: all four gesture rules exercised with injected input on the Simulator

## Summary of Changes

Gesture grammar is now:

| gesture | on empty map | on a known object |
|---|---|---|
| tap | dismiss callout **and** deselect | open its callout |
| long press | drop a pin (+ haptic) | open its callout |

`ExpeditionMapView` gained `.onLongPressMapGesture`, guarded to `state == .began` so it fires exactly once per press. The DSL has no feature-returning long-press variant, so hit-testing goes through `MapViewProxy.visibleFeatures(at:styleLayerIdentifiers:)` against the same layer set the tap uses; tap and long-press dispatch now share `dispatchKnownObject(in:)`.

The proxy is held in a `MapProxyBox` — a plain class, deliberately not `@Observable`, since under `.realtime` it is written every frame and must never invalidate a view. That also consolidated the proxy subscription: the map owns the single `.onMapViewProxyUpdate(.realtime)` and forwards to the parent via `onProxyUpdate`, because two subscriptions would have fought over the same environment value (the scale bar from [[AlaskaRouter-xogw]] was the other one).

`handleMapEmptyTap` no longer drops a pin and no longer peels one overlay per tap — it clears callout and selection together, so the gesture always means the same thing. The pin-drop path moved to `handleMapEmptyLongPress`.

**Verified on Simulator with injected input** (all four rules):

1. tap on empty terrain → no pin appears
2. long press on empty terrain → "Dropped pin" callout, exactly one
3. tap on empty terrain → the open callout dismisses
4. long press on stop 5's marker → "STOP 5 OF 41" callout, not a pin

Deselection confirmed separately: after the dismissing tap, stop 5's marker reverted to its unselected style.
