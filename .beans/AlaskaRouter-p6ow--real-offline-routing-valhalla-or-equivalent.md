---
# AlaskaRouter-p6ow
title: Real offline routing (Valhalla or equivalent)
status: todo
type: feature
priority: high
created_at: 2026-05-19T07:17:46Z
updated_at: 2026-05-19T07:17:46Z
parent: AlaskaRouter-ttvk
---

v1 ships online-only routing (OSRM HTTP) with straight-line / spline fallback when offline. v2 bundles an actual offline router (Valhalla on iOS, Mapbox-OSRM port, or similar). Real engineering: routing graphs are big, app-size budget matters, region partitioning. Unblocks the deep-Alaska use case where there is no network.
