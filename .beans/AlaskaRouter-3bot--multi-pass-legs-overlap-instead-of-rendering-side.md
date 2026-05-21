---
# AlaskaRouter-3bot
title: Multi-pass legs overlap instead of rendering side-by-side
status: todo
type: bug
priority: high
created_at: 2026-05-20T19:41:45Z
updated_at: 2026-05-21T11:13:34Z
parent: AlaskaRouter-xtua
blocked_by:
    - AlaskaRouter-39eu
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


---

## Reopened — both attempted fixes reverted (commit 4558a11)

**What was tried & why it failed:**

1. **Per-point perpendicular offset** (commit d04d815, reverted).
   Each polyline point shifts perpendicular to its LOCAL tangent. Works
   on straight-line geometry (the no-snap demo case I used for matrix
   verification — straight 2-point segments have one constant tangent).
   Breaks catastrophically on OSRM-snapped curvy polylines: at every
   bend the local perpendicular flips, the shifted line doubles back on
   itself, producing concentric loops. User saw this immediately on
   their real iPhone (which has snapped coords from OSRM).

2. **Uniform perpendicular offset** (commit fcc9173, reverted).
   Translate every point in the segment's slice by the same (Δlat, Δlon)
   computed from the slice's start→end direction. By construction can't
   self-intersect — but the shifted ribbon doesn't TRACK the road's
   curves. The whole road-shape is just translated as a block. For long
   segments with bends, the ribbon clearly drifts off the road wherever
   the road curves. User flagged: "ugly lines passing everywhere but
   along the road. This is tremendous regression."

**Bean blocked-by `AlaskaRouter-<spike-id>` (see "Spike" below).**

## Spike — to define before next attempt

This is an algorithm-class problem (offset curves on real road geometry),
not a tuning bug. Need a focused investigation before touching production.

### 1. Define user expectations tightly

Open questions (need answers before geometry work):

- For multi-pass on the SAME road: should each pass visibly TRACK the
  road's curves (offset polyline follows every bend, like two cars in
  adjacent lanes)? Or is "approximately parallel along the corridor"
  enough?
- At sharp bends (mountain switchbacks), is it acceptable for the
  parallel ribbons to compress / cross / behave differently than at
  straight stretches?
- At waypoint joints, can the ribbons have small visual jogs where
  consecutive segments meet, or do they need to be C¹-continuous?
- Color: does each PASS get its own color (current model: color =
  destination block's color, so a return leg in block 2 is all the same
  block-2 color), or does each PASS rotate through a palette
  independent of block?

### 2. Define how the geometry should work

Candidate algorithms (with cost vs quality trade-offs):

- **Native MapLibre `line-offset`**: MLNLineStyleLayer has a `lineOffset`
  property that's rendered at the GPU level — perfect parallel offset
  with bend handling done by the renderer. MapLibreSwiftDSL doesn't
  expose it; would need the unsafeMapViewControllerModifier path to
  create raw layers. Likely the right answer.
- **Per-pass single polyline + native offset**: build ONE
  MLNPolylineFeature per pass (whole-pass coords), one MLNLineStyleLayer
  per pass with lineOffset = slot × W. No segment-level offset math.
- **Per-point perpendicular with smoothing**: keep the source-offset
  approach but smooth perpendiculars (windowed average over K
  neighbors) to suppress flips at bends. Imperfect, still wobbles.
- **True offset curve algorithm (Clipper, etc.)**: heavyweight C++
  dependency. Highest quality but probably out of scope for v1.

### 3. Check what we know about the map

Audit:
- What geometry do we actually have when there's NO network? OSRM is
  online; without it we have only straight-line waypoint→waypoint.
- When OSRM IS available, what does `snappedRouteCoords` actually look
  like for a multi-pass trip — does OSRM return a single contiguous
  polyline that retraces, or N separate polylines?
- Does MapLibre's lineOffset work on a polyline that visits the same
  road twice (out-and-back)?
- For grouping passes: today the signature is direction-invariant
  (sorted quantized samples). Is that the right grouping primitive for
  the chosen algorithm?

### 4. Sketch a spike rig

One stretch of road (e.g., Cantwell → Healy). Synthetic but realistic
OSRM-style polyline. Render:

- 1 pass (baseline — single ribbon)
- 2 passes (forward + return) — both same color, then different colors
- 3 passes (forward + return + forward) — same / two-color variants

For each, capture screenshots at z=8, z=10 (max). Compare against
expectations from step 1. Iterate algorithm until visuals match. THEN
port the winning algorithm to production.

Spike lives in its own directory (e.g., `spikes/D_multipass/`) so we
can throw it away cleanly when done.

## Status

Bean status: in-progress → blocked (blocked-by spike bean).


---

## Reset back to open

Production integration attempt **reverted to `sober-geologist`** (commit b1ee027) after a strong regression. The spike's "4 hardcoded full-route layers" model worked beautifully in isolation but my naive scaling to real trip data (per-leg slicing, direction inference, snap fallback, content fingerprints) produced compounding bugs. Visual result was a single visible ribbon instead of the onion lanes.

The lesson: the spike rendered ONE polyline repeated N times with hardcoded absolute offsets. Production needs to preserve that shape — render each pass as ONE continuous full-extent polyline with one absolute offset. Per-leg fragmentation was the wrong direction.

Bean re-opens. The visual spec lives in 39eu and is still locked. What needs redesigning is the integration architecture.
