---
# AlaskaRouter-2i03
title: Negative cache for confirmed-unroutable legs (avoid re-bisecting dead legs every recompute)
status: completed
type: task
priority: normal
created_at: 2026-06-19T02:58:11Z
updated_at: 2026-06-19T04:09:20Z
---

Follow-up to AlaskaRouter-d0wt (bisection recovery). Today, after recovery snaps the routable legs around an unroutable stop (e.g. Denali centre), the genuinely-unroutable legs stay missing from the SegmentCache. So every geometry recompute (stop edit, possibly cold launch) re-forms a tiny missing run over those legs and re-bisects them — ~3 wasted Valhalla requests per recompute for the Alaska trip. Add a negative cache: persist a per-pair 'no route at this geometry' marker (a RouteSegment variant or sentinel) keyed on the directed coord pair, invalidated when either stop's coordinates change (same 5-decimal key scheme as SegmentCache). perPairGeometries should treat a negative-cached pair as .pending WITHOUT scheduling a re-fetch. Keep it version-stamped like RouteSegment so an engine bump (RoutingEngineVersion.current) re-probes.

## Reframed (user): terminal 'unroutable' leg state, not just a cache

The leg WAS routed (attempted) and the verdict is 'no valid route'. Model it as a first-class terminal state, not a missing/pending pair:
- RouteSegment gains isUnroutable flag (empty polyline). Coord-keyed (auto-invalidates when a stop moves), version-stamped (re-probes on engine bump).
- PairGeometry gains .unroutable: renders as straight dashed line (no road geometry, same visual as pending) but is NEVER put in a missing run / re-fetched.
- pendingPairIndices (dash set) = pending UNION unroutable; pendingSnapKey / retry-on-reconnect = pending ONLY.
- Whole-trip blob persisted only when fully snapped (no dashed legs) so the blob short-circuit never hides the unroutable dashes.
- Export/import: SegmentDTO.isUnroutable (optional, schemaVersion stays 1); restore writes markers; so an imported trip doesn't re-attempt either.
- Recovery + single-pair top-level no-route now WRITE the marker.

- [x] model + cache (RouteSegment.isUnroutable; SegmentCache.store flag + storeUnroutable)
- [x] planner (.unroutable closes runs; stitches straight line)
- [x] RootView wiring (dash=pending∪unroutable; blob persists only when fully snapped; markRunUnroutable on recovery + single-pair no-route)
- [x] export/import round-trip (SegmentDTO.isUnroutable optional; schemaVersion stays 1)
- [x] unit tests (8 new; full suite 131 green)

## Summary of Changes

Terminal 'unroutable' leg state (negative cache), not just a fetch-suppressor:
- RouteSegment.isUnroutable flag (empty geometry); SegmentCache.store threads it + storeUnroutable(). Coord-keyed (moved stop re-attempts) + version-stamped (engine bump re-probes).
- PairGeometry.unroutable: missingRuns treats it as a resolved boundary (never fetched); stitchedPolyline draws a straight dashed line (no road geometry).
- RootView: dash set = pending UNION unroutable; pendingSnapKey/retry = pending only; whole-trip blob persisted only when fully snapped; markRunUnroutable() writes markers from recovery + single-pair top-level no-route.
- Export/import: SegmentDTO.isUnroutable (optional; schemaVersion stays 1 so old files still load); export emits markers, import restores them -> imported trips don't re-probe.
- 8 new unit tests; full suite 131 green.

Note: cross-launch persistence needs a healthy store with the RouteSegment table (see AlaskaRouter-tpoo for the stale-store migration issue); within a session the marker still kills the re-attempt churn.
