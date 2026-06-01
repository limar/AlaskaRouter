// JSON encoding/decoding for routed polylines.
// Used by `Trip.snappedRouteEncoded` (whole-trip blob) and
// `RouteSegment.polylineEncoded` (per-pair cache), AlaskaRouter-un6b.
//
// Format: `[[lat, lon], [lat, lon], ...]`. Chosen for debuggability and
// schema-migration resilience over compactness — 50 KB vs 10 KB for a
// 2000-point Alaska polyline, well within SwiftData's comfort zone.

import Foundation
import CoreLocation

enum PolylineCodec {
    static func encode(_ coords: [CLLocationCoordinate2D]) -> String? {
        let pairs: [[Double]] = coords.map { [$0.latitude, $0.longitude] }
        guard let data = try? JSONSerialization.data(withJSONObject: pairs) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ encoded: String) -> [CLLocationCoordinate2D]? {
        guard let data = encoded.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[Double]]
        else { return nil }
        return arr.compactMap { p in
            guard p.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: p[0], longitude: p[1])
        }
    }
}
