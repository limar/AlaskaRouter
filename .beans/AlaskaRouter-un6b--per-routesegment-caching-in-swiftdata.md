---
# AlaskaRouter-un6b
title: Per-RouteSegment caching in SwiftData
status: todo
type: task
priority: normal
created_at: 2026-05-19T07:16:55Z
updated_at: 2026-05-19T07:16:55Z
parent: AlaskaRouter-xtua
---

Currently OSRMProvider fetches the full A->B->C->...->Z route in one request and caches in memory via snappedRouteCoords + snappedRouteKey. Better: cache per-edge (Waypoint pair) in SwiftData as SegmentGeometry.snapped(polyline, computedAt). Survives app restart, supports incremental edits (insert stop -> only recompute 2 segments), enables pendingSnap visualization per-edge.
