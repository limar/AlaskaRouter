// AlaskaRouter-3bot / AlaskaRouter-pbmw — Pass-aware route rendering.
//
// The route is decomposed into RouteRibbons: short directed polylines, each
// carrying a block color and a perpendicular lineOffset. Coincident roads
// (out-and-backs, return legs, retraces) are fanned out into nested "onion"
// lanes so the user can count how many times the route passes any point.
//
// Offset is OVERLAP-DRIVEN (AlaskaRouter-pbmw): a stretch of road is only
// shifted off-center when it is actually traversed more than once. A road
// driven a single time stays centered (offset 0), even if the trip contains
// out-and-backs elsewhere. This is the fix for "the lone stretch after an
// out-and-back was wrongly shifted as if it were a second pass."

import Foundation
import CoreLocation

/// One ribbon — a maximal run of consecutive legs within a pass that share the
/// same block color AND the same offset lane. One traversal that crosses N
/// blocks emits N ribbons (same offset, meeting at block-boundary waypoints);
/// a traversal whose overlap count changes mid-pass splits there too. Ready
/// for the renderer to drop straight into an MLNLineStyleLayer with native
/// lineOffset.
struct RouteRibbon: Identifiable {
    /// Stable per-ribbon id (used in the layer-id fingerprint).
    let id: Int
    let coords: [CLLocationCoordinate2D]
    /// Multiplier applied to the zoom-interpolated highlight width to get
    /// the ribbon's lineOffset value. The renderer computes
    /// `lineOffset(zoom) = offsetMultiplier × lineWidth(zoom)`, which keeps
    /// the ribbon's inner edge sitting on the polyline center across all
    /// zooms (without this, low-zoom thin lines leave a gap).
    ///
    /// Values per the locked onion spec:
    ///   - single coverage (road driven once) → 0      (no offset, centered)
    ///   - 1st lane, left                       → -0.5   (rank 0)
    ///   - 2nd lane, left                       → -1.5   (rank 1)
    ///   - nth lane, left                       → -(rank + 0.5)
    /// Negative in MapLibre's convention means "left of travel direction";
    /// opposite-direction passes therefore land on opposite absolute sides,
    /// so an out-and-back at -0.5/-0.5 separates into two visible lanes.
    let offsetMultiplier: Double
    /// Block color this ribbon should render in. Determined by the block
    /// of the leg's *destination* waypoint (the same convention used by
    /// the rest of the trip-block model — the segment "enters" the new
    /// block as it arrives at the destination).
    let color: TripColor
    /// True when built from straight-line geometry (no OSRM snap).
    /// Renderer dashes these so the user can see the route is the
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

    /// Decompose the trip into renderable ribbons.
    ///
    /// 1. Slice the base polyline into directed legs (one per stop pair),
    ///    each carrying its block color, direction vector and a
    ///    direction-invariant road signature.
    /// 2. Group legs into passes (contiguous runs with no direction reversal)
    ///    — passes are the *merge units*, so ribbons never span a U-turn and
    ///    out-and-backs stay as two clean directed ribbons.
    /// 3. Group legs by road signature to find real geographic overlap. Legs
    ///    sharing a road are fanned into nested lanes; legs whose road no
    ///    other leg shares stay centered (offset 0).
    /// 4. Walk each pass, emitting a ribbon whenever the block color or the
    ///    offset lane changes.
    func routeRibbons(snappedCoords: [CLLocationCoordinate2D]?) -> [RouteRibbon] {
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

        // Block color lookup: the road LEAVING block N's last stop takes
        // block N+1's color (segment "enters" the new block as it arrives at
        // the destination) — matches the rest of TripBlocks's convention.
        let blocksByWaypointID: [UUID: TripColor] = {
            var m: [UUID: TripColor] = [:]
            for b in self.blocks {
                for wp in b.waypoints { m[wp.id] = b.color }
            }
            return m
        }()

        // 1. Build legs. Each is a directed slice of the base polyline plus
        //    its direction vector, block color, and road signature. Degenerate
        //    legs (zero-length slice) are dropped.
        struct Leg {
            let dir: (Double, Double)
            let coords: [CLLocationCoordinate2D]
            let color: TripColor
            let signature: String
        }
        var legs: [Leg] = []
        for i in 0 ..< stops.count - 1 {
            let s = stops[i].coordinate
            let e = stops[i + 1].coordinate
            let si = waypointIndexes[i]
            let ei = waypointIndexes[i + 1]
            let lo = min(si, ei)
            let hi = max(si, ei)
            guard hi > lo else { continue }
            var coords = Array(baseCoords[lo...hi])
            if si > ei { coords.reverse() }
            legs.append(Leg(
                dir: (e.latitude - s.latitude, e.longitude - s.longitude),
                coords: coords,
                color: blocksByWaypointID[stops[i + 1].id] ?? self.color,
                signature: Trip.roadSignature(coords)
            ))
        }
        guard !legs.isEmpty else { return [] }

        // 2. Group consecutive legs into passes (contiguous runs with no
        //    direction reversal — dot product < 0 against the previous leg).
        //    Passes bound ribbon merging so out-and-backs render as two
        //    separate directed ribbons rather than one folded polyline.
        var passes: [[Int]] = []        // arrays of indices into `legs`
        var current: [Int] = []
        for i in legs.indices {
            if let prev = current.last {
                let p = legs[prev].dir
                let dot = legs[i].dir.0 * p.0 + legs[i].dir.1 * p.1
                if dot < 0 {
                    passes.append(current)
                    current = [i]
                    continue
                }
            }
            current.append(i)
        }
        if !current.isEmpty { passes.append(current) }

        // 3. Overlap-driven offset. Group legs by road signature; legs that
        //    share a signature traverse the same road and get nested lanes.
        //    Lane magnitude grows per same-direction traversal; opposite
        //    directions both start at -0.5 and separate by travel side. A leg
        //    whose road no other leg shares (group size 1) stays centered.
        var legsBySignature: [String: [Int]] = [:]
        for i in legs.indices {
            legsBySignature[legs[i].signature, default: []].append(i)
        }
        var legMultiplier = [Double](repeating: 0, count: legs.count)
        for (_, members) in legsBySignature where members.count >= 2 {
            // `members` are in ascending leg index = trip order.
            let canonical = legs[members[0]].dir
            var forwardRank = 0
            var backwardRank = 0
            for idx in members {
                let dot = legs[idx].dir.0 * canonical.0 + legs[idx].dir.1 * canonical.1
                let rank: Int
                if dot >= 0 { rank = forwardRank; forwardRank += 1 }
                else        { rank = backwardRank; backwardRank += 1 }
                legMultiplier[idx] = -(Double(rank) + 0.5)
            }
        }

        // 4. Emit ribbons. Walk each pass in order; flush a ribbon whenever
        //    the block color or the offset lane changes. Consecutive legs that
        //    share both colors and lane merge into one continuous ribbon.
        var out: [RouteRibbon] = []
        var ribbonIdx = 0
        for pass in passes {
            var curCoords: [CLLocationCoordinate2D] = []
            var curColor: TripColor? = nil
            var curMult = 0.0
            func flush() {
                guard !curCoords.isEmpty, let color = curColor else { return }
                out.append(RouteRibbon(
                    id: ribbonIdx,
                    coords: curCoords,
                    offsetMultiplier: curMult,
                    color: color,
                    isStraightLineFallback: !useSnap
                ))
                ribbonIdx += 1
                curCoords = []
                curColor = nil
            }
            for idx in pass {
                let leg = legs[idx]
                let mult = legMultiplier[idx]
                if curColor == nil {
                    curColor = leg.color
                    curMult = mult
                    curCoords = leg.coords
                } else if curColor == leg.color && curMult == mult {
                    // Same color + lane → extend. Drop duplicate join point.
                    curCoords.append(contentsOf: leg.coords.dropFirst())
                } else {
                    flush()
                    curColor = leg.color
                    curMult = mult
                    curCoords = leg.coords
                }
            }
            flush()
        }
        return out
    }

    /// Direction-invariant signature of a polyline: subsample to a fixed
    /// budget, quantize each point to a ~56 m grid, sort, and join. Two legs
    /// that trace the same road — in either direction — hash equal, which is
    /// how an out-and-back's two legs are recognised as the same road. This is
    /// the leg-granularity heuristic (Tier A): it catches whole-leg retraces
    /// and out-and-backs, but not a retrace that begins mid-leg (handled by
    /// the sub-leg coverage pass, Tier B).
    static func roadSignature(_ coords: [CLLocationCoordinate2D]) -> String {
        guard !coords.isEmpty else { return "" }
        func q(_ c: CLLocationCoordinate2D) -> String {
            let qLat = Int((c.latitude * 2000).rounded())   // 1/2000° ≈ 56 m
            let qLon = Int((c.longitude * 2000).rounded())
            return "\(qLat),\(qLon)"
        }
        let budget = 12
        let n = coords.count
        var samples: [String] = []
        if n <= budget {
            samples.reserveCapacity(n)
            for c in coords { samples.append(q(c)) }
        } else {
            samples.reserveCapacity(budget)
            for i in 0 ..< budget {
                let idx = Int(Double(i) * Double(n - 1) / Double(budget - 1))
                samples.append(q(coords[idx]))
            }
        }
        return samples.sorted().joined(separator: "|")
    }
}
