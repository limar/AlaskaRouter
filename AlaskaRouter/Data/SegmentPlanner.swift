// Partial-fetch planning (AlaskaRouter-2l0i).
//
// Given a trip's ordered waypoints and the per-segment cache, figure out:
//   1. Which consecutive pairs are already cached (free render).
//   2. Which consecutive pairs are missing.
//   3. How to group the missing pairs into contiguous runs we can fetch
//      with a SINGLE routing call per run — the request shape (a list of
//      waypoints A, B, C, D) inherently asks the router for legs A→B,
//      B→C, C→D in one go.
//   4. How to chunk a run that's longer than the routing provider can
//      accept (FOSSGIS Valhalla caps at 20 locations; see
//      `RoutingRequestLimits.maxLocationsPerRoutingRequest`).
//
// Output is a small `RoutingPlan` value type the orchestration code in
// RootView consumes. All functions here are pure — easy to unit-test
// without driving SwiftUI or hitting a network.

import Foundation
import CoreLocation

/// Where each consecutive pair in a trip is sourced from.
enum PairGeometry {
    /// Real snapped road geometry — from the per-segment cache or a
    /// fresh successful provider response.
    case snapped([CLLocationCoordinate2D])
    /// We tried (or want) to fetch this pair but couldn't. The renderer
    /// dashes a straight line for these legs. Same visual semantics as
    /// the trip-wide pendingSnap state today, but per-leg.
    case pending
    /// (AlaskaRouter-2i03) Terminal "no drivable path" verdict — the router
    /// was asked and said this pair can't be routed (e.g. an off-road
    /// stop). Renders the same dashed straight line as `.pending`, but is
    /// NOT a missing pair: the planner never puts it in a fetch run, so we
    /// don't re-attempt it on every recompute. Backed by an `isUnroutable`
    /// row in the segment cache and preserved across export/import.
    case unroutable
}

/// One contiguous run of missing consecutive pairs the planner wants to
/// fetch in a single routing request. `waypoints` is the request payload
/// (length = number of pairs in the run + 1). `firstPairIndex` is the
/// position in the trip's pair list where this run starts — used to
/// place the response back into the per-pair geometry array.
struct MissingRun: Equatable {
    let firstPairIndex: Int
    let waypoints: [CLLocationCoordinate2D]

    var pairCount: Int { max(0, waypoints.count - 1) }
}

enum SegmentPlanner {
    /// Walk consecutive pairs and split into runs of missing geometries.
    /// A "run" is bounded on both sides either by a cached pair or by
    /// the trip's endpoints. Each emitted run carries the waypoints the
    /// routing provider needs to see (one more than the pair count).
    static func missingRuns(
        in geometries: [PairGeometry],
        stops: [CLLocationCoordinate2D]
    ) -> [MissingRun] {
        // geometries.count must equal stops.count - 1 by construction
        // (one geometry per consecutive pair). Defensive guard for tests.
        guard geometries.count + 1 == stops.count, geometries.count >= 1 else {
            return []
        }
        var runs: [MissingRun] = []
        var runStart: Int? = nil
        for i in geometries.indices {
            switch geometries[i] {
            case .snapped, .unroutable:
                // Both are "resolved" pairs that bound a run: `.snapped` has
                // real geometry, `.unroutable` is a terminal no-route we must
                // NOT re-fetch (2i03). Either way it closes any open run.
                if let start = runStart {
                    // Close the run [start, i-1]; needs waypoints
                    // stops[start ... i].
                    let wps = Array(stops[start ... i])
                    runs.append(MissingRun(firstPairIndex: start, waypoints: wps))
                    runStart = nil
                }
            case .pending:
                if runStart == nil { runStart = i }
            }
        }
        if let start = runStart {
            // Close the trailing run [start, geometries.count - 1]; needs
            // waypoints stops[start ... geometries.count].
            let wps = Array(stops[start ... geometries.count])
            runs.append(MissingRun(firstPairIndex: start, waypoints: wps))
        }
        return runs
    }

    /// Split a single run into chunks each no larger than `maxLocations`
    /// waypoints. Successive chunks share a boundary waypoint so the
    /// underlying pair coverage stays contiguous: a 25-waypoint run with
    /// `maxLocations = 10` becomes chunks of 10 + 10 + 7, sharing
    /// boundaries at positions 9 and 18.
    static func chunk(
        _ run: MissingRun,
        maxLocations: Int = RoutingRequestLimits.maxLocationsPerRoutingRequest
    ) -> [MissingRun] {
        // Logic invariant: maxLocations >= 2 (otherwise no pair fits).
        // Anything lower is a config bug; treat as 2 to keep this pure.
        let cap = max(2, maxLocations)
        guard run.waypoints.count > cap else { return [run] }

        var chunks: [MissingRun] = []
        var cursor = 0                                  // index into run.waypoints
        while cursor < run.waypoints.count - 1 {
            let end = min(cursor + cap - 1, run.waypoints.count - 1)
            let slice = Array(run.waypoints[cursor ... end])
            chunks.append(MissingRun(
                firstPairIndex: run.firstPairIndex + cursor,
                waypoints: slice
            ))
            // Share the boundary waypoint with the next chunk so the
            // pair coverage is exact: cursor moves to `end`, not `end+1`.
            cursor = end
        }
        return chunks
    }

    /// Stitch per-pair geometries into a single polyline for the
    /// existing `snappedRouteCoords` channel (and for whole-trip cache
    /// persistence). Cached pairs contribute their snapped geometry;
    /// pending pairs contribute a straight line stops[i] → stops[i+1].
    /// Shared boundary waypoints are deduplicated at the join.
    static func stitchedPolyline(
        geometries: [PairGeometry],
        stops: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard geometries.count + 1 == stops.count, !geometries.isEmpty else { return [] }
        var out: [CLLocationCoordinate2D] = []
        for i in geometries.indices {
            let pairCoords: [CLLocationCoordinate2D]
            switch geometries[i] {
            case let .snapped(coords):   pairCoords = coords
            // Pending and unroutable both lack road geometry → straight line.
            case .pending, .unroutable:  pairCoords = [stops[i], stops[i + 1]]
            }
            if pairCoords.isEmpty { continue }
            if i == 0 {
                out.append(contentsOf: pairCoords)
            } else {
                out.append(contentsOf: pairCoords.dropFirst())
            }
        }
        return out
    }
}
