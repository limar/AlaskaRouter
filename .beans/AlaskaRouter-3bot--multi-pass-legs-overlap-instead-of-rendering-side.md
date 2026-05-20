---
# AlaskaRouter-3bot
title: Multi-pass legs overlap instead of rendering side-by-side
status: completed
type: bug
priority: high
created_at: 2026-05-20T19:41:45Z
updated_at: 2026-05-20T20:47:59Z
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

- [x] Reproduce with `seedDemoReturnLeg` and capture a screenshot of the overlap
- [x] Diagnose which of the four "where to investigate" paths is the root cause — turned out to be #2 (offset constant 100× too small) compounded by missing cos(lat) compensation
- [x] Fix the cause (not paper over with extra offset)
- [x] Verify same-color case (single-block out-and-back) — visible at z=9 and z=10
- [x] Verify different-color case (return leg in a later block) — strong amber + blue contrast
- [x] Verify three-pass case (back-and-forth-and-back) — new seedDemoTripleLeg dev launch arg

## References

- `AlaskaRouter/Data/TripSegments.swift` — offset implementation
- `AlaskaRouter/Map/ExpeditionMapView.swift` (~line 112+) — segment rendering
- `AlaskaRouter/Data/SampleTrip.swift` (~line 49) — `seedDemoReturnLeg` dev seeder
- AlaskaRouter-9axu (completed) — original design + implementation

## Root cause

Two compounding bugs in `AlaskaRouter/Data/TripSegments.swift`:

1. **Constant 100× too small.** `perpendicularOffset` divided the pt-offset by `70_000.0` to convert to coordinate degrees. The correct denominator at z=10 is ~728 (1° latitude = 256 × 2^10 / 360 = 728 screen px). The previous value made a 7pt offset render as 0.07 pixels at z=10 — visually identical to no offset at all.

2. **Mercator longitude stretch not compensated.** The perpendicular rotation treated lat/lon as Cartesian. At lat 64° N, 1° longitude = ~0.44 of 1° latitude in screen pixels — so N–S segments (most of Parks Highway) received roughly half the visual offset of E–W segments. Asymmetric and confusing.

3. **`passOffsetUnit = 7.0` too tight.** Even after fixing the constant, 7pt center-to-center was less than one wash width (14pt at z=10) — the washes would overlap so heavily the ribbons read as one. Bumped to 14pt so cores are clearly parallel and washes only just touch.

## Fix

`AlaskaRouter/Data/TripSegments.swift`:
- `degreesPerPointAtZ10 = 1.0 / 728.0` (replaces the bogus `/ 70_000.0`)
- Added `cosLat` compensation: tangent is computed in "screen-pixel-equivalent degrees" (lon scaled by cos(lat)), rotated 90°, then un-scaled when written back to coords.
- `passOffsetUnit: Float = 14.0` (was 7.0); cap raised to 28pt to match.
- Comments updated to reference 3bot, document the math, and warn that screen offset grows with zoom (deliberate trade).

`AlaskaRouter/Data/SampleTrip.swift`:
- New dev launch arg `seedDemoTripleLeg` — appends a second forward leg after the initial 5 stops (or after the reverse leg if `seedDemoReturnLeg` also set), producing 3-pass / 4-pass synthetic trips for stress-testing offset rendering.

## Verification — matrix of 12 screenshots

Each cell: `2leg|3leg × 1color|2color × z=7|9|10`. Center on Healy (mid-route), 9-stop (or 13-stop) Parks Highway out-and-back / out-and-back-and-out trip.

| | z=7 (far) | z=9 (mid) | z=10 (close) |
|---|---|---|---|
| 2-leg 1-color | Two amber ribbons, close | Two parallel ribbons ✓ | Clearly separated ✓ |
| 2-leg 2-color | Amber + blue parallel ✓ | Strong contrast ✓ | Vivid ✓ |
| 3-leg 1-color | Three close ribbons | Three parallel ribbons ✓ | Clear "lanes" ✓ |
| 3-leg 2-color | Mixed colors, 3 ribbons | Three distinguishable ribbons ✓ | Spread with mixed colors ✓ |

Repro recipes:
```bash
# 2-leg 1-color
launch -seedDemoTrip 1 -seedDemoReturnLeg 1 ...
# 2-leg 2-color
launch -seedDemoTrip 1 -seedDemoReturnLeg 1 -seedDemoSeparator 1 ...
# 3-leg 1-color
launch -seedDemoTrip 1 -seedDemoReturnLeg 1 -seedDemoTripleLeg 1 ...
# 3-leg 2-color
launch -seedDemoTrip 1 -seedDemoReturnLeg 1 -seedDemoTripleLeg 1 -seedDemoSeparator 1 ...
```

Note: a clean SwiftData store is required (the first-launch seed guard skips when DB has any trips). `xcrun simctl erase` between scenarios when iterating.

## Known follow-ups (separate beans recommended if they bite)

- **Zoom-adaptive offset width**: today the offset is a fixed coordinate-degree value, so screen separation grows linearly with zoom (1× at z=10, 4× at z=12, 0.25× at z=8). At very low zoom the ribbons merge into one fatter line; at very high zoom they're widely spread. Acceptable for v1 — the "planning zoom" is z=9..11 and that's where the fix is tuned. If feedback says "too wide at z=14", add a zoom-aware scale.
- **Selected-waypoint sobresaliente halo** overlaps the ribbons heavily at z=10 (concentric ring icon). Not a 3bot concern, but worth noting since the matrix screenshots show it prominently. Track separately if it bugs.
