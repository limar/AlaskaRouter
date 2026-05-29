---
# AlaskaRouter-pbmw
title: 'Bug: single-pass stretch gets onion offset after an out-and-back (A→B→A→C)'
status: in-progress
type: bug
priority: high
created_at: 2026-05-29T15:22:17Z
updated_at: 2026-05-29T15:40:48Z
---

The last stretch after an out-and-back is rendered shifted/offset (as if it were a 2-pass stretch) when it is in fact traversed only once.

## Reproduction
Fairbanks → Santa's Sleigh (North Pole) → Fairbanks → C. The A→B stretch correctly draws a double ribbon (out-and-back). The final A→C stretch draws a single ribbon but it is offset to the left, which is wrong — a single-traversal road must be centered (offset 0).

## UI logic (user-defined, item 1)
At any geographic POINT on the route, the number of parallel ribbons (lanes) the user sees must equal the number of times the route physically passes over that point. Consequences:
- Overlap is a property of GEOMETRY, not waypoint identity. A→B→A' (A'≈A but not exactly) must still double the A-B road.
- A→B→C where the C routing retraces through A→B must double the A-B stretch.
- A road traversed once → exactly 1 lane, centered (offset 0).

## Root cause (item 3)
In Trip.routeRibbons (AlaskaRouter/Data/TripPasses.swift):
- `multiPass` is a TRIP-WIDE boolean (`descriptors.count >= 2`, line ~191) and the per-pass offset is `multiPass ? -(rank + 0.5) : 0` (line ~197), where `rank` is the pass's ordinal within its direction class across the WHOLE trip.
- Therefore once a trip contains ≥2 passes anywhere, EVERY pass is shifted off-center — including passes whose road overlaps nothing. That is exactly the A→C bug.
- Secondary: pass detection is a leg-to-leg direction-reversal heuristic (dot<0), which cannot see geometric retraces (it neither detects forward retraces nor proves non-overlap).

## Plan
- [ ] (1) Lock the UI logic (above) — DONE, written here.
- [ ] (2) Document the current algorithm — DONE (see root cause).
- [ ] (3) Pinpoint the failure — DONE (global multiPass/rank).
- [x] (4) Approach chosen: **Tier A now (per-leg geometric-signature overlap) as a verified checkpoint, then Tier B (sub-leg coverage onion) in the same session**, keeping Tier A as the reset fallback.
- [ ] (5) Implement + verify on simulator (Fairbanks→Santa's→Fairbanks→C). Reset on failure.

## Constraints
We are at the best ribbon-rendering point so far; the onion ((())) currently looks beautiful for clean out-and-backs. Do NOT regress that. Reset the change if the fix doesn't hold.

## Tier A — landed (checkpoint)

Replaced the trip-wide `multiPass`/global-rank offset with **per-leg road-signature overlap grouping** in `Trip.routeRibbons` (TripPasses.swift). Legs that trace the same road get nested onion lanes; a leg whose road no other leg shares stays centered (offset 0). Pass detection is retained only as the ribbon-merge boundary so out-and-backs still render as two clean directed ribbons.

Verified: `xcodebuild test` → DataInvariantTests 11/11 pass, including new `testRouteRibbonsCenterLoneStretchAfterOutAndBack` (A→B→A→C: A–B doubled, A→C centered) and `testRouteRibbonsCenterSharpTurnWithoutRetrace`. Existing onion test (out-and-back -0.5/-0.5) still green.

Limitation (handed to Tier B): a whole-leg signature can't catch a retrace that begins *mid-leg* (A→B→C where the C routing drives back through part of A→B). Tier B adds sub-leg coverage counting.

Still pending: visual verification on the simulator (Fairbanks→Santa's Sleigh→Fairbanks→C).
