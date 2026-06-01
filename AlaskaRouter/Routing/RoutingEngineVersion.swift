// Routing engine version stamp (AlaskaRouter-y3g3).
//
// Bump `current` when the routing engine OR its tuning changes in a way
// that should invalidate existing cached geometry. The cache stamps every
// fresh `RouteSegment` and `Trip.snappedRouteEncoded` with the version
// that produced it; lookups treat a version-mismatched row as a miss,
// triggering a silent re-fetch with the new engine on next snap.
//
// History:
//   0 — implicit pre-versioning. Rows written before the version field
//       existed default to 0. All v0 rows are stale by definition.
//   1 — switched the default provider from public OSRM (router.project-
//       osrm.org / `driving` profile) to FOSSGIS Valhalla
//       (valhalla1.openstreetmap.de) with `costing_options.auto.use_ferry
//       = 1.0`. AMHS ferry sailings (Valdez ↔ Whittier and friends) now
//       route correctly through the Alaska Marine Highway rather than
//       picking the 576 km Glenn Hwy detour.
//
// Why this bump is silent (no migration UI): the cold-launch path will
// see a brief dashed-fallback flicker for trips whose v0 cache is stale,
// then re-render with real geometry after the partial-fetch lands —
// that's the only visible signal. A one-time "your trips are being
// re-routed" toast was considered and rejected as more noise than
// information.

import Foundation

enum RoutingEngineVersion {
    static let current: Int = 1
}
