---
# AlaskaRouter-dd2u
title: Dropped pins should require a long press, not a tap
status: todo
type: bug
priority: high
created_at: 2026-07-27T21:32:58Z
updated_at: 2026-07-27T21:36:47Z
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
- [ ] Long-press duration — system default (~0.5 s) or tuned?
- [ ] Haptic on pin drop? (recommend: yes, `.impact(.medium)` — it is the only feedback that the press "took")
- [ ] Does a plain empty tap also *deselect* the currently selected trip waypoint, or only close the callout?
- [ ] Does long press over a *known object* drop a pin there, or open that object's callout? (recommend: known object wins, same as tap — never bury a real POI under an anonymous pin)

## Todo
- [ ] Agree the behaviour table above
- [ ] Implement: tap-empty → dismiss; long-press-empty → drop pin
- [ ] Verify on device: pan/pinch a busy area for 30 s, confirm zero accidental pins
