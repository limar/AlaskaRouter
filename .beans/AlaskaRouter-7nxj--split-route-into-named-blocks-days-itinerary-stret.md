---
# AlaskaRouter-7nxj
title: Split route into named blocks (days / itinerary stretches)
status: todo
type: feature
priority: high
created_at: 2026-05-19T10:08:36Z
updated_at: 2026-05-19T10:08:36Z
parent: AlaskaRouter-xtua
---

Mental model: each block is one DAY or one stretch of the itinerary. A long trip naturally splits into multiple multi-day blocks (e.g. 'Anchorage → Fairbanks', 'Fairbanks → Deadhorse', 'Deadhorse → Coldfoot'). This was in the original requirements and is high priority core functionality.

Behavior:
- Stop list (bottom sheet) shows blocks as visually-separated groups, with each block named either auto ('First-stop — Last-stop' like 'Fairbanks — Deadhorse') or manually overridable.
- Each block of the route gets a distinct highlight color on the map (auto-assigned from a palette, with the active trip's primary color reserved or anchoring the sequence).
- User adds a block boundary either by inserting an explicit separator in the stop list or by some other intuitive gesture (TBD in UI design — drag-handle to insert? long-press a stop and 'split here'?). Design needs discussion before implementation.

Touches data model, bottom sheet rendering, and the ExpeditionMapView LineStyleLayer (currently a single colored line for the whole trip; needs per-segment coloring keyed by block id).

- [ ] Design UI gesture for inserting/removing/renaming a block boundary (sketch + consult)
- [ ] Extend SwiftData schema: Block model with order + name? + optional color override; Waypoint.block relationship
- [ ] Route rendering: per-segment color from the block of each segment's leading waypoint
- [ ] Bottom sheet: visual separator + block header rows
- [ ] Auto-naming: 'firstWaypoint.label — lastWaypoint.label'
- [ ] Re-block on insert/delete/reorder so blocks remain contiguous and correctly named
- [ ] Decide interaction with the Routing layer (per-segment caching — AlaskaRouter-un6b — may need to track block too)
