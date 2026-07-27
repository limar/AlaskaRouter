---
# AlaskaRouter-xtua
title: v1 — Personal Alaska trip
status: completed
type: milestone
priority: critical
created_at: 2026-05-19T07:15:28Z
updated_at: 2026-07-27T21:37:20Z
---

First dogfooded version. Map look-and-feel + search + trip building + four named polish features. Annotations explicitly deferred to v2. Online routing + spline fallback (real offline routing deferred to v2).

## Summary of Changes

Shipped and field-tested. The whole v1 scope landed: offline MapLibre + Protomaps basemap with the self-rendered OpenTopoMap pack, the FTS5 offline search subsystem, trip building with blocks/multi-pass ribbons, online routing with per-segment caching and unroutable-leg handling, waypoint + POI + dropped-pin callouts, trip export/import, and share-to-external-maps.

Tagged **v1.0.0** at commit 3288dc1 — the build carried on the Alaska expedition, June–July 2026.

**Status correction:** this milestone was flipped to `scrapped` on 2026-06-10 (commit 00939e3, "review beans status") with no rationale recorded, while all of its children shipped. That was a mis-set status, corrected here to `completed`.

The trip produced a usability list, now tracked under **AlaskaRouter-36of (v1.1 — Field Fixes)**, plus AlaskaRouter-ctco (social export) held back for its own release.
