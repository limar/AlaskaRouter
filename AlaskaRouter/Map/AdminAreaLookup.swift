// Runtime admin-area lookup for arbitrary coordinates (AlaskaRouter-4r8l).
//
// When the user taps an empty area of the map, we drop a pin and want to
// show the borough/census-area name in the callout — same "Denali, AK, USA"
// / "Yukon-Koyukuk, AK, USA" format the search-results view uses. The
// build-time pipeline (tools/build-places/build_fts5.py pass 2c) already
// computes `admin_area` for every place by finding the nearest GNIS row
// within 30 km; this is the runtime port of that pass.
//
// Architecture:
//   - On app launch, parse places.geojson once on a background task.
//   - Filter to GNIS-sourced rows that carry a non-empty admin_area
//     (~12 k of the 33 k features). These are our "donors."
//   - Bucket by integer-degree latitude for a cheap bbox prefilter
//     (~0.27° latitude per 30 km, so checking three bands always covers
//     the search radius).
//   - On lookup, scan three adjacent bands; haversine against any donor
//     whose latitude is within 0.30°; return the admin_area of the
//     nearest within 30 km.
//
// Cost:
//   - One-time parse: ~200 ms on iPhone 16 for the 6.7 MB JSON (async).
//   - Per-tap lookup: <1 ms (a few hundred haversines at worst).
//   - Memory: ~12 k × (16 B coord + ~24 B admin) ≈ 500 KB.

import Foundation
import CoreLocation

@MainActor
final class AdminAreaLookup {

    static let shared = AdminAreaLookup()
    private init() {}

    /// Search radius matching `ADMIN_INHERIT_KM` in build_fts5.py.
    private static let radiusKm: Double = 30.0

    /// `latitude band (integer ° rounded down) → donor entries`.
    /// Empty until `startLoad()` completes.
    private var donorBands: [Int: [(coord: CLLocationCoordinate2D, admin: String)]] = [:]
    private var didStart = false

    /// Kick off the background parse. Idempotent — second+ calls are no-ops.
    /// Call once from `App.init` or the root view's `.task` modifier.
    func startLoad() {
        guard !didStart else { return }
        didStart = true
        Task.detached(priority: .utility) {
            let bands = Self.parsePlacesGeoJSON()
            await MainActor.run {
                self.donorBands = bands
            }
        }
    }

    /// Return the admin-area string for the nearest GNIS donor within
    /// `radiusKm` of `coord`. Returns empty string when none is within
    /// range (e.g. far ocean, far inland with sparse GNIS coverage), in
    /// which case the UI should fall back to a country/state label.
    func nearestAdmin(for coord: CLLocationCoordinate2D) -> String {
        // While loading, the bands are empty and we return "" — the UI's
        // "AK, USA" fallback covers it. Lookup remains correct once loaded.
        guard !donorBands.isEmpty else { return "" }

        let band = Int(floor(coord.latitude))
        var bestKm: Double = .infinity
        var bestAdmin: String = ""

        for b in (band - 1)...(band + 1) {
            guard let donors = donorBands[b] else { continue }
            for (donorCoord, donorAdmin) in donors {
                // Cheap latitude prefilter — same 0.30° threshold the
                // Python pass uses.
                if abs(donorCoord.latitude - coord.latitude) > 0.30 { continue }
                let km = Self.haversineKm(coord, donorCoord)
                if km < bestKm {
                    bestKm = km
                    bestAdmin = donorAdmin
                }
            }
        }
        return bestKm <= Self.radiusKm ? bestAdmin : ""
    }

    // MARK: - Loading

    nonisolated private static func parsePlacesGeoJSON() -> [Int: [(CLLocationCoordinate2D, String)]] {
        guard let url = Bundle.main.url(forResource: "places", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = obj["features"] as? [[String: Any]]
        else { return [:] }

        var bands: [Int: [(CLLocationCoordinate2D, String)]] = [:]
        for f in features {
            guard let props = f["properties"] as? [String: Any],
                  let source = props["source"] as? String, source == "gnis",
                  let admin  = props["admin_area"] as? String, !admin.isEmpty,
                  let geom   = f["geometry"] as? [String: Any],
                  let xy     = geom["coordinates"] as? [Double], xy.count >= 2
            else { continue }
            let lon = xy[0], lat = xy[1]
            let band = Int(floor(lat))
            bands[band, default: []].append((
                CLLocationCoordinate2D(latitude: lat, longitude: lon),
                admin
            ))
        }
        return bands
    }

    nonisolated private static func haversineKm(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        let dlat = (b.latitude  - a.latitude)  * .pi / 180
        let dlon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dlat/2) * sin(dlat/2) +
                cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) *
                sin(dlon/2) * sin(dlon/2)
        return 2.0 * 6371.0 * asin(min(1.0, sqrt(h)))
    }
}
