---
# AlaskaRouter-7nxj
title: Split route into named blocks (days / itinerary stretches)
status: completed
type: feature
priority: high
created_at: 2026-05-19T10:08:36Z
updated_at: 2026-05-19T14:07:19Z
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



## Summary of Changes

Three steps, three commits:

1. **Data model (44b124f)** — BlockSeparator @Model with afterWaypointID + back-reference to Trip. Computed Trip.blocks: [TripBlock] derives the rendering blocks from waypoints + separators. Auto-name 'First → Last' per block, auto-color rotates through TripColor palette (block 0 = trip's own color, blocks 1..N = remaining colors).
2. **Bottom-sheet UI (ac9a286)** — sheet stop list now renders trip.listItems (interleaved stops + separators). Separator rows show block-color badge + auto-name + draggable handle. '+ Add block separator' button below the list (visible when 2+ stops). Drag-reorder handles both stops and separators, prunes degenerate separators that lose their anchor.
3. **Map route line (this commit)** — ExpeditionMapView splits the route geometry by block (waypoint coords for straight-line, nearest snap-coord for snapped) and renders one LineStyleLayer per block in its block color. Single shared cream casing under the whole route stays.

Important gotcha discovered in step 3: the MapViewContentBuilder result builder silently produces empty output when a 'for (block, coords) in geoms' loop is used with tuple destructuring. Plain 'for entry in geoms' works. Noted inline at the loop site.

Follow-up beans:
- AlaskaRouter-z57c — Edit block boundaries directly on the map (deferred, depends on landmark clickability)
- AlaskaRouter-<new bean> — Route line color contrast on warm basemap (block colors render but blend with OpenTopoMap; needs palette / width pass)
