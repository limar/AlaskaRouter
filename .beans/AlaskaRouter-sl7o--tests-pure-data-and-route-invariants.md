---
# AlaskaRouter-sl7o
title: 'Tests: pure data and route invariants'
status: completed
type: task
priority: high
created_at: 2026-05-27T08:07:33Z
updated_at: 2026-05-27T08:21:29Z
parent: AlaskaRouter-kupb
---

Add unit tests for stable trip/data behavior.

- [x] Add test factories for in-memory trips, waypoints, and separators
- [x] Test `SmartInsert.position` and order renumbering
- [x] Test `Trip.blocks`, `Trip.listItems`, and degenerate separator handling
- [x] Test snap-cache set/hydrate/stale/clear behavior
- [x] Test `Trip.routeRibbons` straight-line fallback, block color split, and out-and-back pass behavior

## Summary of Changes

Added reusable test factories in `Tests/TestFactories.swift` and route/data invariant coverage in `Tests/DataInvariantTests.swift`. Covered `SmartInsert.position`, `SmartInsert.insertSmart` order renumbering, `Trip.blocks`, `Trip.listItems`, degenerate separator filtering, snapped-route cache hydrate/stale/malformed/clear behavior, and `Trip.routeRibbons` fallback, block split, and out-and-back behavior. Verified with `xcodebuild test`: 11 tests, 0 failures.
