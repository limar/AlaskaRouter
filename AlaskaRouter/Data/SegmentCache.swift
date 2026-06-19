// Per-pair routing cache accessor (AlaskaRouter-un6b).
//
// Wraps the SwiftData `RouteSegment` table with a tiny lookup/store API
// keyed on rounded directed coord pairs. The format of the lookup key
// matches `RouteSegment.key`: "lat,lon→lat,lon" at 5 decimal places
// (~1.1 m) so a re-geocoded stop at the same place still hits.
//
// All access is from the main thread against the shared `ModelContext`.
// A `@MainActor` annotation makes this explicit at the compiler.

import Foundation
import SwiftData
import CoreLocation

@MainActor
struct SegmentCache {
    let context: ModelContext

    init(_ context: ModelContext) { self.context = context }

    static func key(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> String {
        String(
            format: "%.5f,%.5f→%.5f,%.5f",
            from.latitude, from.longitude,
            to.latitude, to.longitude
        )
    }

    /// Look up the cached row for a directed pair, irrespective of its
    /// `routerVersion`. Used by `store(...)` for the upsert path so we
    /// can update a stale row in place instead of leaving an orphan.
    /// Callers that want only fresh (current-engine) geometry should use
    /// `lookupFresh` instead.
    func lookup(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> RouteSegment? {
        let k = Self.key(from: from, to: to)
        var d = FetchDescriptor<RouteSegment>(predicate: #Predicate { $0.key == k })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// AlaskaRouter-y3g3 — lookup that respects the version stamp. A row
    /// whose `routerVersion` doesn't match the current engine is treated
    /// as a cache miss so the snap pipeline silently re-fetches with the
    /// new engine.
    func lookupFresh(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> RouteSegment? {
        guard let seg = lookup(from: from, to: to) else { return nil }
        return seg.routerVersion == RoutingEngineVersion.current ? seg : nil
    }

    /// Returns the cached polyline + leg-distance + leg-duration for every
    /// consecutive pair in `waypoints`, or `nil` if any pair is missing
    /// OR is stamped with an older routing-engine version. On a full hit,
    /// the caller can render without a network call.
    func lookupAllPairs(_ waypoints: [CLLocationCoordinate2D]) -> [RouteSegment]? {
        guard waypoints.count >= 2 else { return nil }
        var out: [RouteSegment] = []
        out.reserveCapacity(waypoints.count - 1)
        for i in 0 ..< waypoints.count - 1 {
            guard let seg = lookupFresh(from: waypoints[i], to: waypoints[i + 1]) else { return nil }
            out.append(seg)
        }
        return out
    }

    @discardableResult
    func store(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        polyline: [CLLocationCoordinate2D],
        distanceMeters: Double,
        durationSeconds: Double,
        at now: Date = .now,
        isUnroutable: Bool = false
    ) -> RouteSegment? {
        guard let encoded = PolylineCodec.encode(polyline) else { return nil }
        let k = Self.key(from: from, to: to)
        if let existing = lookup(from: from, to: to) {
            existing.polylineEncoded = encoded
            existing.distanceMeters = distanceMeters
            existing.durationSeconds = durationSeconds
            existing.computedAt = now
            // (y3g3) Re-stamp on every write so an upsert against a
            // stale-version row brings it forward to the current engine.
            existing.routerVersion = RoutingEngineVersion.current
            // (2i03) Upsert flips the verdict both ways: a pair that used
            // to be unroutable but now snaps clears the flag, and vice versa.
            existing.isUnroutable = isUnroutable
            return existing
        }
        let seg = RouteSegment(
            key: k,
            fromLat: from.latitude, fromLon: from.longitude,
            toLat: to.latitude, toLon: to.longitude,
            polylineEncoded: encoded,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            computedAt: now,
            routerVersion: RoutingEngineVersion.current,
            isUnroutable: isUnroutable
        )
        context.insert(seg)
        return seg
    }

    /// (2i03) Record a terminal "no drivable path" verdict for a directed
    /// pair: an empty-geometry row flagged `isUnroutable`. The planner then
    /// renders a dashed straight line for the leg but never re-fetches it.
    /// Version-stamped and coord-keyed like any segment, so an engine swap
    /// or a moved stop re-probes the pair (see `RouteSegment.isUnroutable`).
    @discardableResult
    func storeUnroutable(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        at now: Date = .now
    ) -> RouteSegment? {
        store(
            from: from, to: to,
            polyline: [],
            distanceMeters: 0,
            durationSeconds: 0,
            at: now,
            isUnroutable: true
        )
    }
}

/// Stitch consecutive cached segments into a single polyline. Each
/// segment's last coordinate equals the next segment's first (the shared
/// endpoint waypoint), so we drop the leading coord of every segment
/// except the first to avoid duplicate vertices at the join.
enum SegmentStitcher {
    static func stitch(_ segments: [RouteSegment]) -> [CLLocationCoordinate2D] {
        var out: [CLLocationCoordinate2D] = []
        for (i, seg) in segments.enumerated() {
            let coords = seg.coordinates
            if i == 0 {
                out.append(contentsOf: coords)
            } else {
                out.append(contentsOf: coords.dropFirst())
            }
        }
        return out
    }
}
