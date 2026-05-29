---
# AlaskaRouter-pbmw
title: 'Bug: single-pass stretch gets onion offset after an out-and-back (A→B→A→C)'
status: completed
type: bug
priority: high
created_at: 2026-05-29T15:22:17Z
updated_at: 2026-05-29T16:04:23Z
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
- [x] (5) Implemented + verified on simulator (Fairbanks→Santa's Sleigh→Fairbanks→Yukon River Camp): double drawn double, single drawn single, doubled corridor renders as clean parallel lines. User confirmed best result so far.

## Constraints
We are at the best ribbon-rendering point so far; the onion ((())) currently looks beautiful for clean out-and-backs. Do NOT regress that. Reset the change if the fix doesn't hold.

## Tier A — landed (checkpoint)

Replaced the trip-wide `multiPass`/global-rank offset with **per-leg road-signature overlap grouping** in `Trip.routeRibbons` (TripPasses.swift). Legs that trace the same road get nested onion lanes; a leg whose road no other leg shares stays centered (offset 0). Pass detection is retained only as the ribbon-merge boundary so out-and-backs still render as two clean directed ribbons.

Verified: `xcodebuild test` → DataInvariantTests 11/11 pass, including new `testRouteRibbonsCenterLoneStretchAfterOutAndBack` (A→B→A→C: A–B doubled, A→C centered) and `testRouteRibbonsCenterSharpTurnWithoutRetrace`. Existing onion test (out-and-back -0.5/-0.5) still green.

Limitation (handed to Tier B): a whole-leg signature can't catch a retrace that begins *mid-leg* (A→B→C where the C routing drives back through part of A→B). Tier B adds sub-leg coverage counting.

Still pending: visual verification on the simulator (Fairbanks→Santa's Sleigh→Fairbanks→C).

## Tier B — landed (sub-leg coverage onion)

Reworked `Trip.routeRibbons` to compute offset at SUB-LEG granularity. Every leg edge is rasterized onto a ~56 m grid; coverage = number of distinct legs per cell, read at each edge's midpoint. Lanes are assigned per cell (canonical = lowest-index covering leg; same-direction nest, opposite-direction separate by travel side). Short constant-coverage runs (<120 m) are dissolved into a neighbour to kill junction speckle and forward/return geometry-mismatch noise. A leg can now emit several ribbons when its overlap count changes partway along it.

Catches the mid-leg retrace case (A→B→C where the C routing drives back through part of A→B) that the Tier A whole-leg signature could not.

Tuning knobs: `coverageCellsPerDegree` (grid resolution), `minCoverageRunMeters` (speckle threshold).

Verified: `xcodebuild test` → DataInvariantTests 12/12 pass, incl. new `testRouteRibbonsDoubleMidLegRetrace` (centered head + doubled tail + doubled return) and all Tier A / existing onion tests still green.

Still pending: **visual verification on the simulator** — both the reported A→B→A→C (Fairbanks→Santa's Sleigh→Fairbanks→C) and the look of the onion overall. Tier A is committed separately (afd73ec) as the reset fallback if Tier B regresses the look.

## Tier B artifact — fixing (dilated coverage read)

On-device (Fairbanks→Santa's Sleigh→Fairbanks→Yukon River Camp): single/double classification is CORRECT, but the doubled stretch fragmented into dozens of short round-capped ribbon stubs that read as fat dots / "pregnant ants" instead of the clean two parallel lines Tier A produced.

Cause: coverage was read at each edge's exact midpoint cell; OSRM forward vs return geometry isn't vertex-aligned, so coverage flickered 1↔2 along the shared corridor → many tiny sub-ribbons → round-cap blobs at every join.

Fix: read coverage from a DILATED neighbourhood (midpoint cell + its 8 neighbours, ~±56 m) so a shared corridor reads constant coverage and collapses to one clean ribbon per direction, while still allowing genuine mid-leg coverage changes. Keeps all 12 unit tests valid.

## Summary of Changes

Root cause: `Trip.routeRibbons` set ribbon offset from a trip-wide `multiPass` flag + a global per-direction rank, so any trip with ≥2 passes shifted *every* ribbon off-centre — including roads driven only once (the reported A→B→A→C bug).

Fix shipped in three commits on `claude/ecstatic-bouman-ed317a` (based on 84670ab):
- **afd73ec (Tier A)** — offset is overlap-driven via per-leg direction-invariant road signatures. Legs sharing a road nest into onion lanes; a leg whose road no other leg shares stays centered (offset 0). Pass detection retained only as the ribbon-merge boundary.
- **e90e595 (Tier B)** — coverage computed at SUB-LEG granularity by rasterizing every edge onto a ~56 m grid, so retraces that begin mid-leg (A→B→C routing back through part of A→B) also double correctly. A leg can emit several ribbons when its overlap count changes partway.
- **2f8769b (de-speckle)** — coverage read from a dilated neighbourhood (midpoint cell + 8 neighbours) so a shared corridor reads constant coverage and renders as one clean ribbon per direction instead of fragmenting into round-capped 'pregnant ant' stubs.

Tuning knobs in TripPasses.swift: `coverageCellsPerDegree`, `minCoverageRunMeters`.

Tests: DataInvariantTests 12/12 pass, incl. new `testRouteRibbonsCenterLoneStretchAfterOutAndBack`, `testRouteRibbonsCenterSharpTurnWithoutRetrace`, `testRouteRibbonsDoubleMidLegRetrace`; existing onion behaviour preserved.
