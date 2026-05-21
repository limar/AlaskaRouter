// AlaskaRouter-3bot — Pass-aware route rendering, step-by-step rebuild.
//
// Step 1 (done): one polyline at offset 0 for the whole trip route.
// Step 2 (now):  detect passes (maximal runs of legs with no direction
//                reversal) and emit one RoutePass per pass, each with its
//                full-extent polyline + absolute lineOffset.
//
// Subsequent steps will add: color-per-block, more pass ranks (3+ passes),
// onion polish.

import Foundation
import CoreLocation

/// One pass through a stretch of road, ready for the renderer to drop
/// straight into a single MLNLineStyleLayer with native lineOffset.
struct RoutePass: Identifiable {
    /// Stable per-pass id (used in the layer-id fingerprint).
    let id: Int
    let coords: [CLLocationCoordinate2D]
    /// Multiplier applied to the zoom-interpolated highlight width to get
    /// the pass's lineOffset value. The renderer computes
    /// `lineOffset(zoom) = offsetMultiplier × lineWidth(zoom)`, which keeps
    /// the pass's inner edge sitting on the polyline center across all
    /// zooms (without this, low-zoom thin lines leave a gap).
    ///
    /// Values per the locked onion spec:
    ///   - single pass             → 0      (no offset, centered)
    ///   - 1st lane, left          → -0.5   (rank 0)
    ///   - 2nd lane, left          → -1.5   (rank 1)
    ///   - nth lane, left          → -(rank + 0.5)
    /// Negative in MapLibre's convention means "left of travel direction";
    /// opposite-direction passes therefore land on opposite absolute sides.
    let offsetMultiplier: Double
    /// True when the pass was built from straight-line geometry (no OSRM
    /// snap). Renderer dashes these so the user can see the route is the
    /// offline-fallback approximation.
    let isStraightLineFallback: Bool
}

extension Trip {

    /// Highlight core width in points at z=10. The unit of the onion model.
    static let highlightCoreWidthPt: Double = 10.0

    /// The trip's full driven path as a single polyline. Used in step 1 and
    /// retained for callers that don't need the multi-pass split.
    func fullRouteCoords(snappedCoords: [CLLocationCoordinate2D]?) -> [CLLocationCoordinate2D]? {
        if let snap = snappedCoords, snap.count >= 2 { return snap }
        let stops = orderedWaypoints
        guard stops.count >= 2 else { return nil }
        return stops.map(\.coordinate)
    }

    /// Decompose the trip into passes. A pass is a maximal sequence of
    /// consecutive legs (waypoint→waypoint segments) with no direction
    /// reversal. Out-and-back = 2 passes. Forward only = 1 pass. Forward-
    /// return-forward = 3 passes.
    ///
    /// Each returned pass carries its full polyline and an absolute
    /// `lineOffsetPt` value sized per the locked onion spec:
    ///   - 1 pass total            → offset 0 (centered on the road)
    ///   - 2+ passes total         → offset `(rank + 0.5) × W` to the pass's
    ///                                left (negative in MapLibre's convention)
    func routePasses(snappedCoords: [CLLocationCoordinate2D]?) -> [RoutePass] {
        let stops = orderedWaypoints
        guard stops.count >= 2 else { return [] }

        let useSnap = (snappedCoords?.count ?? 0) >= 2
        let baseCoords = snappedCoords ?? stops.map(\.coordinate)

        // Monotonic waypoint → polyline-index mapping. OSRM's polyline
        // visits the trip's waypoints in trip order (retracing for return
        // legs), so walking the cursor forward and finding the closest
        // point at-or-after the previous cursor position handles retraces
        // correctly. For the offline fallback (no snap), trivial 1:1
        // mapping.
        let waypointIndexes: [Int] = {
            if !useSnap { return Array(stops.indices) }
            var cursor = 0
            var result: [Int] = []
            for wp in stops {
                var bestIdx = cursor
                var bestDist = Double.infinity
                for i in cursor ..< baseCoords.count {
                    let d = SmartInsert.haversine(baseCoords[i], wp.coordinate)
                    if d < bestDist { bestDist = d; bestIdx = i }
                }
                result.append(bestIdx)
                cursor = bestIdx
            }
            return result
        }()

        // 1. Compute leg direction vectors (waypoint i → i+1 in lat/lon).
        struct Leg {
            let startStop: Int
            let endStop: Int
            let dir: (Double, Double)
        }
        var legs: [Leg] = []
        for i in 0 ..< stops.count - 1 {
            let s = stops[i].coordinate
            let e = stops[i + 1].coordinate
            legs.append(Leg(
                startStop: i, endStop: i + 1,
                dir: (e.latitude - s.latitude, e.longitude - s.longitude)
            ))
        }

        // 2. Group consecutive legs into passes by detecting direction
        //    reversals (dot product < 0 against the previous leg's vector).
        var passLegRanges: [[Int]] = []  // each entry = list of leg indices
        var current: [Int] = []
        for (i, leg) in legs.enumerated() {
            if let prevIdx = current.last {
                let prev = legs[prevIdx].dir
                let dot = leg.dir.0 * prev.0 + leg.dir.1 * prev.1
                if dot < 0 {
                    passLegRanges.append(current)
                    current = [i]
                    continue
                }
            }
            current.append(i)
        }
        if !current.isEmpty { passLegRanges.append(current) }

        // 3. Classify each pass's direction against the first pass
        //    (canonical), and track rank within each direction.
        struct PassDescriptor {
            let legIndices: [Int]
            let isSameDirAsCanonical: Bool
            let rank: Int
        }
        var canonicalVec: (Double, Double)? = nil
        var forwardRank = 0
        var backwardRank = 0
        var descriptors: [PassDescriptor] = []
        for legIndices in passLegRanges {
            // End-to-end vector of this pass.
            let firstLeg = legs[legIndices.first!]
            let lastLeg  = legs[legIndices.last!]
            let s = stops[firstLeg.startStop].coordinate
            let e = stops[lastLeg.endStop].coordinate
            let vec: (Double, Double) = (e.latitude - s.latitude, e.longitude - s.longitude)
            if canonicalVec == nil {
                canonicalVec = vec
            }
            let canonical = canonicalVec!
            let dot = vec.0 * canonical.0 + vec.1 * canonical.1
            let same = dot >= 0
            let rank: Int
            if same {
                rank = forwardRank
                forwardRank += 1
            } else {
                rank = backwardRank
                backwardRank += 1
            }
            descriptors.append(PassDescriptor(
                legIndices: legIndices,
                isSameDirAsCanonical: same,
                rank: rank
            ))
        }

        // 4. Build each pass's polyline + offset multiplier.
        let multiPass = descriptors.count >= 2
        var out: [RoutePass] = []
        for (passIdx, d) in descriptors.enumerated() {
            let firstLegIdx = d.legIndices.first!
            let lastLegIdx  = d.legIndices.last!
            let firstStop = legs[firstLegIdx].startStop
            let lastStop  = legs[lastLegIdx].endStop
            let startIdx = waypointIndexes[firstStop]
            let endIdx   = waypointIndexes[lastStop]
            let lo = min(startIdx, endIdx)
            let hi = max(startIdx, endIdx)
            guard hi > lo else { continue }
            var coords = Array(baseCoords[lo...hi])
            if startIdx > endIdx { coords.reverse() }

            // Multiplier: 0 if single-pass (centered), else -(rank + 0.5)
            // so each pass's inner edge tracks the polyline center across
            // all zoom levels (renderer multiplies by zoom-interp lineWidth).
            let multiplier: Double = multiPass ? -(Double(d.rank) + 0.5) : 0

            out.append(RoutePass(
                id: passIdx,
                coords: coords,
                offsetMultiplier: multiplier,
                isStraightLineFallback: !useSnap
            ))
        }
        return out
    }
}
