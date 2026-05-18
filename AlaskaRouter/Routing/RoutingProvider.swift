// Snap-to-road routing for AlaskaRouter (v1).
//
// Strategy (see memory: project_routing_strategy.md):
//   - v1 uses the OSM-Foundation OSRM public demo router (no API key, polite
//     rate-limited use). Returns full-resolution GeoJSON polyline + distance
//     + duration for the given waypoint sequence.
//   - If the request fails (no network, server down, rate-limit), the caller
//     is expected to render a spline / straight-line fallback and mark the
//     route as pendingSnap until the network monitor re-fires this.
//   - Later v1.5 / v2 plug in OpenRouteService (user-provided key) or a
//     bundled Valhalla graph for true offline routing.

import Foundation
import CoreLocation

protocol RoutingProvider: Sendable {
    /// Snap-to-road a sequence of waypoints. Returns the geometry plus
    /// total distance/duration on success, throws on failure (network, http
    /// error, server reply not "Ok"). Concrete impls are responsible for
    /// being polite (User-Agent, rate-limits).
    func snap(waypoints: [CLLocationCoordinate2D]) async throws -> RoutingResult
}

struct RoutingResult: Sendable {
    /// Polyline geometry: full-resolution coordinates along snapped roads.
    let coordinates: [CLLocationCoordinate2D]
    /// Total distance in meters (sum across all snapped segments).
    let distanceMeters: Double
    /// Total drive duration in seconds.
    let durationSeconds: Double
}

enum RoutingError: Error {
    case insufficientWaypoints
    case http(statusCode: Int)
    case decoding(String)
    case server(code: String)   // OSRM's `code` field when not "Ok"
}

// MARK: - OSRM public router

struct OSRMProvider: RoutingProvider {
    let baseURL: URL
    let profile: String
    let userAgent: String

    init(baseURL: URL = URL(string: "https://router.project-osrm.org")!,
         profile: String = "driving",
         userAgent: String = "AlaskaRouter/0.1 (personal expedition planner)")
    {
        self.baseURL = baseURL
        self.profile = profile
        self.userAgent = userAgent
    }

    func snap(waypoints: [CLLocationCoordinate2D]) async throws -> RoutingResult {
        guard waypoints.count >= 2 else {
            throw RoutingError.insufficientWaypoints
        }
        let coordsString = waypoints
            .map { "\($0.longitude),\($0.latitude)" }
            .joined(separator: ";")
        let path = "/route/v1/\(profile)/\(coordsString)"
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "geometries", value: "geojson"),
        ]
        guard let url = components.url else {
            throw RoutingError.decoding("invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RoutingError.http(statusCode: http.statusCode)
        }
        let decoded: OSRMResponse
        do {
            decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
        } catch {
            throw RoutingError.decoding("\(error)")
        }
        guard decoded.code == "Ok", let route = decoded.routes.first else {
            throw RoutingError.server(code: decoded.code)
        }
        let coords = route.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return .init(latitude: pair[1], longitude: pair[0])
        }
        return RoutingResult(
            coordinates: coords,
            distanceMeters: route.distance,
            durationSeconds: route.duration
        )
    }

    // MARK: - OSRM response shape

    private struct OSRMResponse: Decodable {
        let code: String
        let routes: [Route]
        struct Route: Decodable {
            let geometry: Geometry
            let distance: Double
            let duration: Double
        }
        struct Geometry: Decodable {
            let coordinates: [[Double]]
        }
    }
}
