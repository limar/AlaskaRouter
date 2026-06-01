---
# AlaskaRouter-2l0i
title: 'Partial-fetch routing: only fetch missing segments, render per-leg dashed for failures'
status: todo
type: feature
priority: high
created_at: 2026-06-01T09:14:58Z
updated_at: 2026-06-01T09:14:58Z
blocked_by:
    - AlaskaRouter-un6b
---

## Why

[AlaskaRouter-un6b] lands the per-RouteSegment cache and the cross-trip / revert-to-known-state wins. It does NOT change the API call shape: when any pair is missing, it still falls through to a whole-trip OSRM call. This bean closes the loop:

1. Group missing pairs into contiguous runs and fire ONE OSRM call PER RUN (in parallel) — typical add/delete becomes 1 partial call instead of 1 whole-trip call. Payload shrinks; the trip's other legs are never re-fetched.
2. Per-leg dashed visualization: a failed run only dashes its own legs, the cached legs still render as real roads.

This is the offline-editing experience: edit one stop, the rest of the route stays drawn for real, only the touched bit goes dashed until you're back online.

## TODOs

- [ ] Group missing-pair indices into contiguous runs in `RootView.scheduleSnapForCurrentTrip`.
- [ ] Fire one OSRM call per run in parallel (`withTaskGroup`).
- [ ] Decompose each run's response into per-pair polylines; cache them; merge with cached neighbors.
- [ ] On any run failure (429 / transport), keep cached pairs visible and mark only the failed pairs as pendingSnap.
- [ ] Extend `RouteRibbon` / `routeRibbons` so individual ribbons can carry a "this leg is pending" flag; renderer dashes only those.
- [ ] Tests: insert / delete / reorder against a mocked RoutingProvider; assert per-run call count.
