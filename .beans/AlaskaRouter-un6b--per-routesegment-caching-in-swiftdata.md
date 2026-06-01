---
# AlaskaRouter-un6b
title: Per-RouteSegment caching in SwiftData
status: completed
type: task
priority: high
created_at: 2026-05-19T07:16:55Z
updated_at: 2026-06-01T09:28:17Z
parent: AlaskaRouter-xtua
---

Currently OSRMProvider fetches the full A->B->C->...->Z route in one request and caches in memory via snappedRouteCoords + snappedRouteKey. Better: cache per-edge (Waypoint pair) in SwiftData as SegmentGeometry.snapped(polyline, computedAt). Survives app restart, supports incremental edits (insert stop -> only recompute 2 segments), enables pendingSnap visualization per-edge.


## Scope refinement (2026-06-01)

See the routing-API audit in conversation that produced [AlaskaRouter-bhs4]. Confirmed today: separator changes don't fire a snap, only waypoint mutations do — and *every* waypoint mutation re-snaps the *entire* trip because the cache (`Trip.snappedRouteEncoded`) is keyed on the full ordered lat/lon sequence. This bean fixes that.

### Data layer

- New SwiftData `@Model RouteSegment`:
  - `fromLat, fromLon, toLat, toLon: Double` — directed pair, rounded to 5 decimals (~1.1 m), four-tuple is the natural key.
  - `polylineEncoded: String` — same JSON `[[lat,lon],...]` encoding as `Trip.snappedRouteEncoded` for parity.
  - `distanceMeters, durationSeconds: Double` — preserved from OSRM response per-leg.
  - `computedAt: Date` — for the 60-day hygiene TTL (configurable, default permanent for v1).
- Direction matters (one-way roads), so the key is directed. `(A→B)` and `(B→A)` are distinct rows.

### Lookup / write API

- `SegmentCache.lookup(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> RouteSegment?`
- `SegmentCache.store(from: , to: , polyline: , distance: , duration: , at: Date = .now)`
- All accesses on main thread, against the shared `ModelContext`.

### Snap pipeline changes (RootView)

1. On waypoint-sequence change (`scheduleSnapForCurrentTrip`), consult the segment cache for *each consecutive pair* first.
2. If all hit → stitch the polylines (dedupe shared endpoint vertices) → set `snappedRouteCoords` immediately, no network call. Persist the assembled polyline to `Trip.snappedRouteEncoded` as the cold-launch hydration shortcut.
3. If any miss → batch *only the missing pairs* into one OSRM request via `/route/v1/driving/{a};{b};{c};...`. Decompose the response by the legs array → write each new segment to the cache → stitch with the cached neighbors. Persist the whole assembly to `Trip.snappedRouteEncoded` too.
4. On 429 / network failure for the missing-pairs call, keep the cached-segment polylines visible (real roads) and mark only the missing legs as `pendingSnap` (dashed). This is the "edit-while-offline" win: today's behavior wipes the entire snap on any edit.

### Free side-effect on the existing whole-trip path

Even before the partial-fetch path lands, the *very first* successful whole-trip snap should decompose into per-segment cache rows. That way the next edit immediately benefits.

### Polyline decomposition

OSRM's `legs[i].steps` aren't needed — the merged geometry coordinates + `legs[i].annotation.nodes` give us per-leg slices, but we already do the monotonic waypoint→polyline mapping in `routeRibbons` and `legDistancesMeters`. Refactor that mapping into a single `Trip.waypointIndexesInPolyline(_:)` helper and reuse it here.

### Keep both caches

- `Trip.snappedRouteEncoded` (whole-trip JSON blob) — cold-launch hydration shortcut. One read + decode beats 39 segment stitches.
- `RouteSegment` (per-pair) — edit fast path + offline partial visualization + cross-trip reuse.
- They're not redundant; they serve different access patterns. Populate the whole-trip blob as a *derived artifact* of the segment cache after each successful settling.

### Acceptance criteria

- Insert one stop into a 40-stop trip → at most 1–2 segment OSRM calls (NOT 39).
- Reorder one stop → at most 3 segment OSRM calls.
- Edit a stop while offline → cached segments still render as real roads; only the touched legs go dashed.
- Cross-trip: stops shared between trips reuse cached segments without re-fetching.
- Schema migration is additive (new @Model, existing Trip fields untouched) — no migration risk.

### TODOs

**Phase 1 scope (this bean):** populate the per-segment cache as a side effect of every successful whole-trip snap, and short-circuit to no-network rendering when every pair is already cached (cross-trip reuse + revert-to-known-state wins). Partial-fetch + per-leg pendingSnap visualization moved to [AlaskaRouter-2l0i].

- [x] `@Model RouteSegment` declared and added to the SwiftData `Schema(...)` in AlaskaRouterApp.
- [x] `Data/SegmentCache.swift` with lookup/store accessors keyed on rounded directed coord pairs.
- [x] Refactor the polyline encode/decode helpers out of `Trip` so RouteSegment can reuse them.
- [x] On every successful whole-trip OSRM response: split the merged polyline by waypoint indices and write a row per consecutive pair.
- [x] `RootView.scheduleSnapForCurrentTrip`: before debounce+fetch, check whether every pair already has a cached segment. If yes → stitch + render, no network call. Else → fall through to today's whole-trip OSRM path.
- [x] Tests: cross-trip reuse / revert-to-known-state covered by SegmentCacheTests at the cache layer; end-to-end RootView-edit integration is verified via dogfooding.

### Blocked-by

[AlaskaRouter-41no](.beans/AlaskaRouter-41no--exponential-backoff-for-routing-snap-on-429-networ.md) (exponential backoff) is not strictly required first, but landing it in the same change set means the segment-cache path inherits sane retry behavior immediately.

## Summary of Changes

**New:** PolylineCodec (Data/PolylineCodec.swift), RouteSegment @Model (in Data/TripModels.swift), SegmentCache + SegmentStitcher (Data/SegmentCache.swift), Tests/SegmentCacheTests.swift covering directional keys, 5-decimal rounding, lookup/store upsert, full-pairs lookup, and the shared-endpoint dedupe in the stitcher.

**Schema:** Schema(...) in AlaskaRouterApp now lists RouteSegment.self. SwiftData lightweight migration handles the new entity automatically — no existing-data risk.

**Refactor:** the monotonic waypoint→polyline-index mapping moved from inline blocks in routeRibbons and legDistancesMeters into a single static Trip.monotonicWaypointIndexes(polyline:waypoints:) helper, which the snap pipeline also uses to decompose OSRM responses. Trip's encode/decode delegate to PolylineCodec.

**OSRM provider:** RoutingResult now carries a legs: [Leg] breakdown (distance + duration per consecutive pair).

**Snap pipeline (RootView):**
- scheduleSnapForCurrentTrip consults the whole-trip cache first, then the segment cache. If every pair is cached, the stitched polyline is rendered without a network call.
- On every successful OSRM call, storeSegments decomposes the merged polyline using the monotonic helper and writes one cache row per pair. The whole-trip cache is still persisted as the cold-launch hydration shortcut.

**Effect:**
- Cross-trip reuse: opening a new trip whose stops were visited in an old trip → 0 OSRM calls if all pairs are cached.
- Revert-to-known-state: delete a stop then undo → 0 OSRM calls.
- First-time builds: same 1 OSRM call as before, but populates the per-segment cache as a free side effect.

**Build / tests:** 57/57 tests pass (37 pre-existing + 20 new across SegmentCacheTests, PolylineCodecTests, MonotonicWaypointIndexesTests).

**Out of scope (moved to [AlaskaRouter-2l0i]):** partial-fetch (only fetching missing pairs instead of the whole trip on any miss) and per-leg pendingSnap visualization. Those land in the follow-up bean.
