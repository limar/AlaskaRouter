---
# AlaskaRouter-2l0i
title: 'Partial-fetch routing: only fetch missing segments, render per-leg dashed for failures'
status: completed
type: feature
priority: high
created_at: 2026-06-01T09:14:58Z
updated_at: 2026-06-01T16:54:37Z
blocked_by:
    - AlaskaRouter-un6b
---

## Why

[AlaskaRouter-un6b] lands the per-RouteSegment cache and the cross-trip / revert-to-known-state wins. It does NOT change the API call shape: when any pair is missing, it still falls through to a whole-trip OSRM call. This bean closes the loop:

1. Group missing pairs into contiguous runs and fire ONE OSRM call PER RUN (in parallel) — typical add/delete becomes 1 partial call instead of 1 whole-trip call. Payload shrinks; the trip's other legs are never re-fetched.
2. Per-leg dashed visualization: a failed run only dashes its own legs, the cached legs still render as real roads.

This is the offline-editing experience: edit one stop, the rest of the route stays drawn for real, only the touched bit goes dashed until you're back online.

## TODOs

- [x] Group missing-pair indices into contiguous runs via SegmentPlanner.missingRuns.
- [x] Fire one routing call per chunk in parallel (withTaskGroup) in RootView.runPartialSnap.
- [x] Decompose via Trip.monotonicWaypointIndexes + writeChunkToCache; segment cache absorbs the per-pair rows.
- [x] Per-chunk error handling: success → record + cache; rate-limited / noRoute / transport → leave pairs in pendingPairIndices; retry policy only advances if NO chunk succeeded.
- [x] routeRibbons grew a `pendingPairIndices: Set<Int>?` overload; per-leg isFallback drives RouteRibbon.isStraightLineFallback so the renderer dashes only the pending legs.
- [x] SegmentPlannerTests (12) covering missing-run detection, chunking with shared boundaries, and stitched-polyline assembly; RoutingRequestLimitsTests asserting the production cap stays under Valhalla's hard limit. End-to-end with a mocked provider is parked as a follow-up since the planner pieces are pure-functional and covered.


## Scope expansion (2026-06-01)

This bean now also unblocks [AlaskaRouter-y3g3] (ferries via Valhalla). Valhalla's public FOSSGIS server has a hard 20-locations-per-request cap, so the chunking + per-run partial-fetch design in this bean becomes load-bearing — not just an optimization.

### Hard requirements

- **Constant `maxLocationsPerRoutingRequest`** — small (proposed `10`). Every request to the routing provider is split so it never exceeds this cap. Reasoning in code comment: the public Valhalla cap is 20; we stay well under to (a) tolerate occasional limit tightening, (b) keep failures granular (a 5-pair run failing dashes only 5 legs, not 19), (c) keep payloads small for slow Alaska LTE.
- **Debug assertion** at the routing-call entry point: `assert(coords.count <= maxLocationsPerRoutingRequest, "...")`. Comment must explain the assertion exists to catch partial-fetch logic regressions — anyone bypassing the chunking would trip this in debug. Production builds don't crash (per the [no-crashes rule]); the chunking guarantee is enforced by construction in release.
- **Parallel firing** of independent runs via `withTaskGroup` so a 40-stop cold-cache build doesn't serialize 5 requests across 5 seconds.

## Summary of Changes

**New files**
- AlaskaRouter/Routing/RoutingRequestLimits.swift — constant maxLocationsPerRoutingRequest = 10 + assertChunked debug tripwire. File header documents the three reasons for the cap (FOSSGIS Valhalla hard limit, failure granularity, polite payload size).
- AlaskaRouter/Data/SegmentPlanner.swift — pure-functional planner: PairGeometry enum (.snapped / .pending), MissingRun struct, missingRuns(in:stops:), chunk(_:maxLocations:), stitchedPolyline(geometries:stops:).
- Tests/SegmentPlannerTests.swift — 13 unit tests.

**Modified**
- AlaskaRouter/Routing/RoutingProvider.swift — OSRMProvider.snap now calls RoutingRequestLimits.assertChunked at the boundary. Production builds don't crash on oversized requests (per the no-crashes rule); the assertion is a debug-only tripwire for partial-fetch logic regressions.
- AlaskaRouter/Data/TripPasses.swift — Trip.routeRibbons gained a pendingPairIndices overload. Per-leg isFallback substitutes straight-line geometry for pending pairs and drives RouteRibbon.isStraightLineFallback. Ribbon flush now also splits on a fallback-flag change so cached and pending stretches don't merge.
- AlaskaRouter/Data/TripGeometryCache.swift — routeRibbons accessor + ribbons cache key now include pendingPairIndices.
- AlaskaRouter/Map/ExpeditionMapView.swift — propagates pendingPairIndices through syncTripRouteLayer.
- AlaskaRouter/App/RootView.swift — the orchestration rewrite:
  - New @State pendingPairIndices.
  - scheduleSnapForCurrentTrip resolves per-pair geometries from the segment cache, renders immediately (cached parts as real, missing as dashed), and only schedules a fetch for the missing runs.
  - runPartialSnap chunks each missing run and fires all chunks in parallel via withTaskGroup. Per-chunk ChunkOutcome separates success / rate-limited / noRoute / transport. Retry policy advances only when no chunk succeeded.
  - Whole-trip cache (kp9h) is still persisted, but only when every pair has snapped geometry — partial states stay as the per-segment cache only.

**Effect**
- Add one stop to a 40-stop trip → at most 2 chunks fetched (the two pairs touching the new stop). Other 38 legs draw immediately from cache as real roads.
- Delete one stop → 1 chunk fetched (the new bridging pair). Rest of the route stays as real roads throughout.
- Edit offline → cached legs render as real roads; just the touched legs dash dashed-straight until the next connectivity attempt.
- Cold start with full segment cache (e.g., a trip you routed yesterday) → zero network calls, full real-road render.

**Build / tests**
70/70 pass (57 + 13 new). Per-chunk request size is bounded by RoutingRequestLimits.maxLocationsPerRoutingRequest = 10, well below FOSSGIS Valhalla's hard cap of 20 — paving the way for [AlaskaRouter-y3g3] (Valhalla ferries) which goes in next.
