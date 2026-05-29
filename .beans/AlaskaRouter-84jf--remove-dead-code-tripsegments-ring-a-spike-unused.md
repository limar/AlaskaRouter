---
# AlaskaRouter-84jf
title: Remove dead code (TripSegments, Ring A spike, unused helpers)
status: completed
type: task
priority: normal
created_at: 2026-05-29T17:30:10Z
updated_at: 2026-05-29T17:30:10Z
---

Cleanup pass requested after the ribbon work revealed duplicate/dead modules.

## Removed
- TripSegments.swift (whole file): passOffsetSegments / TripSegment / perpendicularOffset — superseded by routeRibbons (TripPasses.swift), zero external callers.
- Ring A spike (ExpeditionMapView): installRingASpike, addSpikeLayer, addRoadReferenceLine, windowedTangentOffset, movingAverage + the -spikeRingA LaunchArg + its gated call site. Explicit throwaway (AlaskaRouter-39eu); the "is native lineOffset usable" question is answered — routeRibbons uses it.
- fullRouteCoords (TripPasses): no callers.
- blockGeometries, isMultiBlock (TripBlocks): no callers.
- straightRouteCoords(for:) (ExpeditionMapView): no callers.

Kept SampleTrip (used at app bootstrap).

## Summary of Changes
Deleted one file and ~260 lines of dead code across ExpeditionMapView/TripPasses/TripBlocks/LaunchArgs. Regenerated the Xcode project (folder-sourced). Build + DataInvariantTests 14/14 green. Manual reference scan, not a compiler sweep — more internal dead code may exist.
