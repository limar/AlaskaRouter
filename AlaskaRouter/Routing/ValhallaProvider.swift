// Valhalla routing provider for AlaskaRouter v1 (AlaskaRouter-y3g3).
//
// Why Valhalla instead of OSRM?
//
//   OSRM's default car profile assigns ferries a fixed slow speed
//   (~5 km/h) at preprocess time and minimizes route time at query
//   time, so any ferry of meaningful length loses to a road
//   alternative. Concretely: Valdez ↔ Whittier via the AMHS car ferry
//   (~146 km, ~6 h scheduled, properly tagged in OSM) loses to a
//   ~487 km Glenn Hwy + AK 4 drive that OSRM thinks is faster. There
//   is no query-time knob to fix this — the speed is baked into the
//   precompiled graph.
//
//   Valhalla exposes `costing_options.auto.use_ferry` as a per-request
//   float in [0, 1]. Setting it to 1.0 strongly prefers ferries, and
//   AMHS sailings (which carry real `duration=` tags in OSM) get their
//   correct ~6 h sailing time. With this provider, the Valdez ↔
//   Whittier probe returns a 145 km / 6 h 7 m route via "Alaska Marine
//   Highway - Whittier-Valdez Ferry."
//
// Backend: the public FOSSGIS Valhalla demo at
// `https://valhalla1.openstreetmap.de`. Operated under fair-use rules
// documented at https://github.com/valhalla/valhalla/discussions/3373:
//   - 1 call / user / sec, 100 calls / sec total (token-bucket)
//   - Hard max 20 locations per /route request (we cap at 10 via
//     RoutingRequestLimits — see AlaskaRouter-2l0i)
//   - `X-Client-Id` header is requested for published apps; we always
//     send `dev.alaskarouter.AlaskaRouter`
//   - "Not for production for third parties" — fine for personal dogfood
//     and OSS / TestFlight; for App Store at scale we'd need to either
//     self-host Valhalla or move to a paid provider. See
//     [AlaskaRouter-p6ow] (real offline routing) for the v2 plan.
//
// Response decoding: we ask Valhalla for `format=osrm` +
// `shape_format=geojson` so the response shape matches the existing
// OSRMResponse decoder almost verbatim — `routes[0].geometry` is a
// GeoJSON LineString, `routes[0].legs[].distance/duration` are present,
// no top-level `code` field. The legacy OSRMProvider stays around as
// an alternate backend.

import Foundation
import CoreLocation

struct ValhallaProvider: RoutingProvider {
    let baseURL: URL
    /// `costing_options.auto.use_ferry` value. 1.0 = strongly prefer ferries,
    /// the right default for Alaska where AMHS sailings are first-class
    /// trip legs. Drop to 0.5–0.7 if a user disables ferry preference
    /// later (see [AlaskaRouter-y3g3] open question #2).
    let useFerry: Double
    let clientId: String
    let userAgent: String

    init(baseURL: URL = URL(string: "https://valhalla1.openstreetmap.de")!,
         useFerry: Double = 1.0,
         clientId: String = "dev.alaskarouter.AlaskaRouter",
         userAgent: String = "AlaskaRouter/0.1 (personal expedition planner)")
    {
        self.baseURL = baseURL
        self.useFerry = useFerry
        self.clientId = clientId
        self.userAgent = userAgent
    }

    func snap(waypoints: [CLLocationCoordinate2D]) async throws -> RoutingResult {
        guard waypoints.count >= 2 else {
            throw RoutingError.insufficientWaypoints
        }
        // (2l0i) Tripwire — partial-fetch planner is the only intended
        // caller; oversize requests would also hit Valhalla's hard 20-
        // location cap. Debug-only, see RoutingRequestLimits.
        RoutingRequestLimits.assertChunked(waypoints.count)

        let body = RequestBody(
            locations: waypoints.map { Location(lat: $0.latitude, lon: $0.longitude, type: "break") },
            costing: "auto",
            costing_options: CostingOptions(auto: AutoOptions(use_ferry: useFerry)),
            format: "osrm",
            shape_format: "geojson",
            directions_options: DirectionsOptions(units: "kilometers")
        )
        let bodyData = try JSONEncoder().encode(body)

        var request = URLRequest(url: baseURL.appendingPathComponent("route"))
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Valhalla can take a few seconds on the public demo, especially
        // for long routes that pass through ferry networks.
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // (d0wt) Valhalla reports "no drivable path between these
            // locations" as HTTP 400. Under format=osrm the body mirrors
            // OSRM: { "code": "NoRoute", "message": "Impossible route
            // between points" } (verified live). See isNoRouteErrorBody.
            // We must NOT fold that permanent, geometry-bound verdict into
            // the generic .http bucket — upstream maps .http(400) the same
            // as a 429 throttle, which would send a genuinely-unroutable
            // stop into the rate-limit backoff loop forever. Decode the
            // body and surface a dedicated .noRoute so the orchestrator can
            // bisect the run and salvage the routable legs around the bad
            // stop. Anything else (429 throttle, 5xx, malformed request)
            // stays .http.
            if http.statusCode == 400, Self.isNoRouteErrorBody(data) {
                throw RoutingError.noRoute(reason: "Valhalla 400/442: no path for input")
            }
            throw RoutingError.http(statusCode: http.statusCode)
        }
        let decoded: ValhallaOSRMResponse
        do {
            decoded = try JSONDecoder().decode(ValhallaOSRMResponse.self, from: data)
        } catch {
            throw RoutingError.decoding("\(error)")
        }
        guard let route = decoded.routes.first else {
            // Valhalla returns 400 on no-route, but defensively treat
            // an empty routes array as a server-side no-route signal.
            throw RoutingError.server(code: "no_routes")
        }
        let coords = route.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return .init(latitude: pair[1], longitude: pair[0])
        }
        // Valhalla's `format=osrm` puts ONE leg per pair of waypoints in
        // `route.legs`, matching OSRM's shape — perfect drop-in for the
        // RoutingResult.legs contract used by SegmentCache.
        let legs: [RoutingResult.Leg] = route.legs.map {
            .init(distanceMeters: $0.distance, durationSeconds: $0.duration)
        }
        return RoutingResult(
            coordinates: coords,
            distanceMeters: route.distance,
            durationSeconds: route.duration,
            legs: legs
        )
    }

    // MARK: - Request shape

    /// Encoded with snake_case keys to match the Valhalla JSON contract
    /// directly — no need for a CodingKeys workaround when the Swift
    /// property names already use snake_case.
    fileprivate struct Location: Encodable {
        let lat: Double
        let lon: Double
        let type: String
    }
    fileprivate struct AutoOptions: Encodable {
        let use_ferry: Double
    }
    fileprivate struct CostingOptions: Encodable {
        let auto: AutoOptions
    }
    fileprivate struct DirectionsOptions: Encodable {
        let units: String
    }
    fileprivate struct RequestBody: Encodable {
        let locations: [Location]
        let costing: String
        let costing_options: CostingOptions
        let format: String
        let shape_format: String
        let directions_options: DirectionsOptions
    }

    // MARK: - Response shape (format=osrm + shape_format=geojson)

    fileprivate struct ValhallaOSRMResponse: Decodable {
        let routes: [Route]
        struct Route: Decodable {
            let geometry: Geometry
            let distance: Double
            let duration: Double
            let legs: [Leg]
        }
        struct Leg: Decodable {
            let distance: Double
            let duration: Double
        }
        struct Geometry: Decodable {
            let coordinates: [[Double]]
        }
    }

    // MARK: - Error-body classification (AlaskaRouter-d0wt)

    /// Valhalla error bodies on a non-2xx status. There are TWO shapes and
    /// we can receive either, so we decode both sets of keys:
    ///
    ///   - OSRM-format (what we actually get): because we ask for
    ///     `format=osrm`, the server mirrors OSRM's error envelope —
    ///     `{ "code": "NoRoute", "message": "Impossible route between
    ///     points" }`. Verified live against valhalla1.openstreetmap.de.
    ///   - Native Valhalla: `{ "error_code": 442, "error": "No path could
    ///     be found for input" }`. Kept as a fallback in case a future
    ///     server build / a non-osrm path surfaces it.
    fileprivate struct ValhallaErrorBody: Decodable {
        // Native Valhalla shape.
        let error_code: Int?
        let error: String?
        // OSRM-format shape (the one returned under format=osrm).
        let code: String?
        let message: String?
    }

    /// Native Valhalla "no path" error-code family. 442 = "No path could be
    /// found for input". Kept as a set so sibling codes can be added.
    static let noRouteErrorCodes: Set<Int> = [442]

    /// OSRM-format `code` values that mean "no drivable path": `NoRoute`
    /// (no route connects the points) and `NoSegment` (a coordinate can't
    /// be snapped to any road — exactly the off-road-waypoint case).
    static let noRouteOSRMCodes: Set<String> = ["NoRoute", "NoSegment"]

    /// Decide whether a non-2xx response body is Valhalla telling us a leg
    /// has no drivable path (permanent) vs. some other 400 (malformed
    /// request, exceeded-max-locations, invalid options) that we'd rather
    /// retry / surface as a transport error. Pure & static so it's
    /// unit-testable without the network. Checks both error shapes by code,
    /// then falls back to the message text as a guard against code drift.
    static func isNoRouteErrorBody(_ data: Data) -> Bool {
        guard let err = try? JSONDecoder().decode(ValhallaErrorBody.self, from: data) else {
            return false
        }
        if let code = err.error_code, noRouteErrorCodes.contains(code) { return true }
        if let osrmCode = err.code, noRouteOSRMCodes.contains(osrmCode) { return true }
        let text = ((err.error ?? "") + " " + (err.message ?? "")).lowercased()
        if text.contains("no path") || text.contains("impossible route") { return true }
        return false
    }
}

// MARK: - Request body inspection for tests
//
// Tests need to assert the outbound request body without hitting the
// network. We expose a tiny helper that builds the same JSON payload
// `snap` would send, so the test can decode and verify field shape /
// `use_ferry` value / X-Client-Id headers.

extension ValhallaProvider {
    /// Build the JSON request body bytes a `snap(waypoints:)` call would
    /// send. Pure function — no network. Test-only entrypoint; keep the
    /// real call routed through `snap`.
    func requestBodyData(for waypoints: [CLLocationCoordinate2D]) throws -> Data {
        let body = RequestBody(
            locations: waypoints.map { Location(lat: $0.latitude, lon: $0.longitude, type: "break") },
            costing: "auto",
            costing_options: CostingOptions(auto: AutoOptions(use_ferry: useFerry)),
            format: "osrm",
            shape_format: "geojson",
            directions_options: DirectionsOptions(units: "kilometers")
        )
        return try JSONEncoder().encode(body)
    }
}
