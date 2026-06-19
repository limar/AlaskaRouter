---
# AlaskaRouter-2i03
title: Negative cache for confirmed-unroutable legs (avoid re-bisecting dead legs every recompute)
status: todo
type: task
priority: normal
created_at: 2026-06-19T02:58:11Z
updated_at: 2026-06-19T02:58:11Z
---

Follow-up to AlaskaRouter-d0wt (bisection recovery). Today, after recovery snaps the routable legs around an unroutable stop (e.g. Denali centre), the genuinely-unroutable legs stay missing from the SegmentCache. So every geometry recompute (stop edit, possibly cold launch) re-forms a tiny missing run over those legs and re-bisects them — ~3 wasted Valhalla requests per recompute for the Alaska trip. Add a negative cache: persist a per-pair 'no route at this geometry' marker (a RouteSegment variant or sentinel) keyed on the directed coord pair, invalidated when either stop's coordinates change (same 5-decimal key scheme as SegmentCache). perPairGeometries should treat a negative-cached pair as .pending WITHOUT scheduling a re-fetch. Keep it version-stamped like RouteSegment so an engine bump (RoutingEngineVersion.current) re-probes.
