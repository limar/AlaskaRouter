---
# AlaskaRouter-3bot
title: Multi-pass legs overlap instead of rendering side-by-side
status: todo
type: bug
priority: high
created_at: 2026-05-20T19:41:45Z
updated_at: 2026-05-20T19:42:40Z
parent: AlaskaRouter-xtua
---

Out-and-back legs on the same road segment still draw on top of each other instead of being offset to parallel ribbons. Reproduces both same-color (one block forth-and-back) and different-color (return leg in a later block). The AlaskaRouter-9axu offset implementation in TripSegments.swift is not producing the expected visual separation.

## What the user sees

When a trip has overlapping legs (out-and-back, return loop, shared spur), the ribbon segments on the shared road still render on top of each other instead of being offset to parallel ribbons. Reported in two flavors:

- **Same color** — a single block contains "Cantwell → Fairbanks → Cantwell" (forth and back, same block, same color). Expected: two parallel ribbons of the same color. Actual: one ribbon (the second pass draws over the first).
- **Different color** — block 1 ends at Fairbanks; block 2 starts from Fairbanks and returns through the same road. Expected: two parallel ribbons of different colors. Actual: still overlapping.

## History

`AlaskaRouter-9axu` (completed) introduced the multi-pass offset rendering:
- Per-segment polylines (`Trip.passOffsetSegments`)
- Direction-invariant road signature for grouping overlapping passes
- Perpendicular offset by `signed slot × ~7pt`

Implementation lives in `AlaskaRouter/Data/TripSegments.swift` (`perpendicularOffset`, `passOffsetSegments`, signature builder around line 188).

A dev launch arg `seedDemoReturnLeg` (in `Data/SampleTrip.swift`) creates an out-and-back trip on the Parks Highway specifically to exercise this rendering — useful for reproduction.

## Where to investigate

1. **Signature grouping** — does the road-signature actually match both directions of the same road? Quantization granularity may be too tight; both directions need to land in the same group. Check `TripSegments.swift` ~line 188.
2. **Offset application** — is `perpendicularOffset` being computed but the rendered polyline still using the un-offset coords? Look for a code path that bypasses `shiftedCoords`.
3. **Render pipeline** — does `ExpeditionMapView` actually pull from `passOffsetSegments` or fall back to `straightRouteCoords` / `snappedRouteCoords` for whole-trip drawing? The fallback would explain "no offset at all."
4. **OSRM snap vs straight-line** — if the segments compared come from different sources (one snapped, one straight-line), signatures will diverge. Look for a per-pass source mismatch.

## Repro

```bash
xcrun simctl launch booted dev.alaskarouter.AlaskaRouter \
  -seedDemoTrip 1 -seedDemoReturnLeg 1 -tripDetent collapsed \
  -hasSeenWelcome 1 -initialZoom 8
```
Expect parallel ribbons on the Parks Highway between Cantwell and Fairbanks; observe overlap.

## Checklist

- [ ] Reproduce with `seedDemoReturnLeg` and capture a screenshot of the overlap
- [ ] Diagnose which of the four "where to investigate" paths is the root cause
- [ ] Fix the cause (not paper over with extra offset)
- [ ] Verify same-color case (single-block out-and-back)
- [ ] Verify different-color case (return leg in a later block)
- [ ] Verify three-pass case if achievable (back-and-forth-and-back)

## References

- `AlaskaRouter/Data/TripSegments.swift` — offset implementation
- `AlaskaRouter/Map/ExpeditionMapView.swift` (~line 112+) — segment rendering
- `AlaskaRouter/Data/SampleTrip.swift` (~line 49) — `seedDemoReturnLeg` dev seeder
- AlaskaRouter-9axu (completed) — original design + implementation
