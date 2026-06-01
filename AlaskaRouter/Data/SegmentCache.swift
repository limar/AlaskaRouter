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

    func lookup(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> RouteSegment? {
        let k = Self.key(from: from, to: to)
        var d = FetchDescriptor<RouteSegment>(predicate: #Predicate { $0.key == k })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// Returns the cached polyline + leg-distance + leg-duration for every
    /// consecutive pair in `waypoints`, or `nil` if any pair is missing.
    /// On a full hit, the caller can render without a network call.
    func lookupAllPairs(_ waypoints: [CLLocationCoordinate2D]) -> [RouteSegment]? {
        guard waypoints.count >= 2 else { return nil }
        var out: [RouteSegment] = []
        out.reserveCapacity(waypoints.count - 1)
        for i in 0 ..< waypoints.count - 1 {
            guard let seg = lookup(from: waypoints[i], to: waypoints[i + 1]) else { return nil }
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
        at now: Date = .now
    ) -> RouteSegment? {
        guard let encoded = PolylineCodec.encode(polyline) else { return nil }
        let k = Self.key(from: from, to: to)
        if let existing = lookup(from: from, to: to) {
            existing.polylineEncoded = encoded
            existing.distanceMeters = distanceMeters
            existing.durationSeconds = durationSeconds
            existing.computedAt = now
            return existing
        }
        let seg = RouteSegment(
            key: k,
            fromLat: from.latitude, fromLon: from.longitude,
            toLat: to.latitude, toLon: to.longitude,
            polylineEncoded: encoded,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            computedAt: now
        )
        context.insert(seg)
        return seg
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
