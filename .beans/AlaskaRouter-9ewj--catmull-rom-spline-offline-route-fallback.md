---
# AlaskaRouter-9ewj
title: Catmull-Rom spline offline route fallback
status: scrapped
type: feature
priority: normal
created_at: 2026-05-19T07:17:08Z
updated_at: 2026-05-29T14:57:23Z
parent: AlaskaRouter-xtua
---

Currently when OSRM is unreachable, the route renders as a straight-line dashed polyline (pendingSnap). Strategy doc says: replace with a Catmull-Rom spline through the waypoints, marked pendingSnap. Auto-upgrades to real road geometry via NWPathMonitor on reconnect (already implemented). Spline gives a non-jarring fallback that still looks like a route, not a survey vector.
