---
# AlaskaRouter-lqfq
title: Renumber stops after deleting a middle waypoint
status: completed
type: bug
priority: high
created_at: 2026-05-28T09:06:15Z
updated_at: 2026-05-31T16:48:12Z
---

When a new trip has three stops and the user deletes the middle waypoint, the remaining final stop should become stop #2 everywhere. Instead, its marker and bottom-sheet row can still display #3.

## Acceptance Criteria

- [x] Add a regression test that creates three waypoints, deletes the middle one, and expects remaining display numbers to be 1 and 2.
  - Suspected root cause: SwiftData relationship still includes the deleted waypoint during immediate renumbering, so the final stop keeps order 2.
- [x] Fix the data/UI numbering source so bottom-sheet rows renumber after deletion.
- [x] Fix or preserve map marker numbering so marker icons renumber after deletion.
- [x] Run focused tests.

## Summary of Changes

- Added a regression test for deleting the middle stop from a three-stop trip and expecting surviving display numbers 1 and 2.
- Added Trip.renumberWaypoints(excluding:) to compact order values while ignoring SwiftData objects pending deletion.
- Routed bottom-sheet trash/swipe deletion and map callout deletion through the shared renumber helper.
- Verified with focused DataInvariantTests and the full AlaskaRouter test scheme.
