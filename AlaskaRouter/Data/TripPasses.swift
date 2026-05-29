// AlaskaRouter-3bot / AlaskaRouter-pbmw — Pass-aware route rendering.
//
// The route is decomposed into RouteRibbons: short directed polylines, each
// carrying a block color and a perpendicular lineOffset. Coincident roads
// (out-and-backs, return legs, retraces) are fanned out into nested "onion"
// lanes so the user can count how many times the route passes any point.
//
// Offset is OVERLAP-DRIVEN and computed at SUB-LEG granularity (Tier B,
// AlaskaRouter-pbmw): every edge of the snapped polyline is rasterized onto a
// coarse grid and we count how many distinct legs cover each cell. A stretch
// is only shifted off-center where it is actually traversed more than once —
// even if the overlap begins in the middle of a leg (A→B→C where the routing
// to C drives back through part of A→B). A road driven once stays centered.

import Foundation
import CoreLocation

/// One ribbon — a maximal run of consecutive edges sharing the same block
/// color AND the same offset lane. One traversal that crosses N blocks emits
/// N ribbons; a traversal whose overlap count changes mid-leg splits there
/// too. Ready for the renderer to drop straight into an MLNLineStyleLayer
/// with native lineOffset.
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

    // Onion tuning knobs.
    /// Grid resolution for "is this the same road" coverage counting.
    /// 1/2000° ≈ 56 m cells. Coarser → more eager to merge near-parallel
    /// roads; finer → more prone to splitting one road into two lanes.
    private static let coverageCellsPerDegree: Double = 2000.0
    /// Minimum on-the-ground length (metres) of a constant-coverage run.
    /// Shorter runs are dissolved into a neighbour, which kills speckle from
    /// junction stubs and forward/return geometry-simplification mismatches.
    private static let minCoverageRunMeters: Double = 120.0

    /// The trip's full driven path as a single polyline. Retained for callers
    /// that don't need the multi-pass split.
    func fullRouteCoords(snappedCoords: [CLLocationCoordinate2D]?) -> [CLLocationCoordinate2D]? {
        if let snap = snappedCoords, snap.count >= 2 { return snap }
        let stops = orderedWaypoints
        guard stops.count >= 2 else { return nil }
        return stops.map(\.coordinate)
    }

    /// Decompose the trip into renderable ribbons.
    ///
    /// 1. Slice the base polyline into directed legs (one per stop pair),
    ///    each carrying its block color and overall direction vector.
    /// 2. Group legs into passes (contiguous runs with no direction reversal)
    ///    — passes are the *merge units*, so ribbons never span a U-turn and
    ///    out-and-backs stay as two clean directed ribbons.
    /// 3. Rasterize every leg edge onto a coarse grid and count how many
    ///    distinct legs cover each cell → per-edge coverage. Shared cells get
    ///    nested onion lanes; cells covered once stay centered.
    /// 4. Smooth short coverage runs, then walk each pass emitting a ribbon
    ///    whenever the block color or the offset lane changes.
    func routeRibbons(snappedCoords: [CLLocationCoordinate2D]?) -> [RouteRibbon] {
        let stops = orderedWaypoints
        guard stops.count >= 2 else { return [] }

        let useSnap = (snappedCoords?.count ?? 0) >= 2
        let baseCoords = snappedCoords ?? stops.map(\.coordinate)

        // Monotonic waypoint → polyline-index mapping. OSRM's polyline visits
        // the trip's waypoints in trip order (retracing for return legs), so a
        // forward-only cursor that snaps each waypoint to the closest point
        // at-or-after the previous one handles retraces correctly. For the
        // offline fallback (no snap), a trivial 1:1 mapping.
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

        // Block color lookup: the road LEAVING block N's last stop takes block
        // N+1's color (segment "enters" the new block as it arrives at the
        // destination) — matches the rest of TripBlocks's convention.
        let blocksByWaypointID: [UUID: TripColor] = {
            var m: [UUID: TripColor] = [:]
            for b in self.blocks {
                for wp in b.waypoints { m[wp.id] = b.color }
            }
            return m
        }()

        // 1. Build legs: directed slice of the base polyline + overall
        //    direction vector + block color. Degenerate (zero-length) legs are
        //    dropped.
        struct Leg {
            let dir: (Double, Double)
            let coords: [CLLocationCoordinate2D]
            let color: TripColor
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
                color: blocksByWaypointID[stops[i + 1].id] ?? self.color
            ))
        }
        guard !legs.isEmpty else { return [] }

        // 2. Group consecutive legs into passes (contiguous runs with no
        //    direction reversal — dot product < 0 against the previous leg).
        //    Passes bound ribbon merging so an out-and-back renders as two
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

        // 3. Sub-leg coverage. Rasterize every leg edge onto a ~56 m grid and
        //    record which legs cover each cell. Reading coverage at each
        //    edge's midpoint (rather than per whole leg) is what catches a
        //    retrace that begins mid-leg.
        let q = Trip.coverageCellsPerDegree
        func cellKey(_ c: CLLocationCoordinate2D) -> Int64 {
            let la = Int64((c.latitude * q).rounded())
            let lo = Int64((c.longitude * q).rounded())
            return (la << 32) ^ (lo & 0xFFFF_FFFF)
        }
        let stepDeg = 1.0 / q / 2.0     // sample edges at ~half a cell
        var cellLegs: [Int64: Set<Int>] = [:]
        for (li, leg) in legs.enumerated() {
            let pts = leg.coords
            for k in 0 ..< pts.count - 1 {
                let a = pts[k], b = pts[k + 1]
                let dLat = b.latitude - a.latitude
                let dLon = b.longitude - a.longitude
                let len = (dLat * dLat + dLon * dLon).squareRoot()
                let n = max(1, min(2000, Int(len / stepDeg)))
                for sIdx in 0 ... n {
                    let t = Double(sIdx) / Double(n)
                    let key = cellKey(.init(
                        latitude: a.latitude + dLat * t,
                        longitude: a.longitude + dLon * t
                    ))
                    cellLegs[key, default: []].insert(li)
                }
            }
        }

        // Per-cell lane multiplier per leg (only where coverage ≥ 2). The
        // canonical direction is the lowest-index covering leg's; same-
        // direction traversals nest (−0.5, −1.5, …), opposite-direction
        // traversals start at −0.5 and separate by travel side. Computed per
        // cell, so it stays consistent along a shared corridor.
        var cellLaneMult: [Int64: [Int: Double]] = [:]
        for (key, set) in cellLegs where set.count >= 2 {
            let members = set.sorted()
            let canonical = legs[members[0]].dir
            var forwardRank = 0
            var backwardRank = 0
            var m: [Int: Double] = [:]
            for idx in members {
                let dot = legs[idx].dir.0 * canonical.0 + legs[idx].dir.1 * canonical.1
                let rank: Int
                if dot >= 0 { rank = forwardRank; forwardRank += 1 }
                else        { rank = backwardRank; backwardRank += 1 }
                m[idx] = -(Double(rank) + 0.5)
            }
            cellLaneMult[key] = m
        }

        // 4. Per leg → per-edge multiplier (read at the edge midpoint), then
        //    dissolve short runs, then segment into sub-ribbons. A leg can now
        //    contribute several pieces if its overlap changes along the way.
        struct SubRibbon { let mult: Double; let coords: [CLLocationCoordinate2D] }
        func subRibbons(forLeg li: Int) -> [SubRibbon] {
            let pts = legs[li].coords
            let edgeCount = pts.count - 1
            guard edgeCount >= 1 else { return [] }

            var mult = [Double](repeating: 0, count: edgeCount)
            var lengths = [Double](repeating: 0, count: edgeCount)
            for k in 0 ..< edgeCount {
                let a = pts[k], b = pts[k + 1]
                let mid = CLLocationCoordinate2D(
                    latitude: (a.latitude + b.latitude) / 2,
                    longitude: (a.longitude + b.longitude) / 2
                )
                mult[k] = cellLaneMult[cellKey(mid)]?[li] ?? 0
                lengths[k] = SmartInsert.haversine(a, b)
            }
            Trip.dissolveShortRuns(&mult, lengths: lengths, minRun: Trip.minCoverageRunMeters)

            var result: [SubRibbon] = []
            var curMult = mult[0]
            var curPts: [CLLocationCoordinate2D] = [pts[0], pts[1]]
            for k in 1 ..< edgeCount {
                if mult[k] == curMult {
                    curPts.append(pts[k + 1])
                } else {
                    result.append(SubRibbon(mult: curMult, coords: curPts))
                    curMult = mult[k]
                    curPts = [pts[k], pts[k + 1]]   // share boundary vertex
                }
            }
            result.append(SubRibbon(mult: curMult, coords: curPts))
            return result
        }

        // Emit ribbons. Walk each pass in order; flush whenever the block
        // color or the offset lane changes. Consecutive pieces sharing both
        // merge into one continuous ribbon.
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
            for li in pass {
                let color = legs[li].color
                for sub in subRibbons(forLeg: li) {
                    if curColor == nil {
                        curColor = color
                        curMult = sub.mult
                        curCoords = sub.coords
                    } else if curColor == color && curMult == sub.mult {
                        curCoords.append(contentsOf: sub.coords.dropFirst())
                    } else {
                        flush()
                        curColor = color
                        curMult = sub.mult
                        curCoords = sub.coords
                    }
                }
            }
            flush()
        }
        return out
    }

    /// Dissolve any maximal run of equal-multiplier edges whose summed length
    /// is below `minRun` into a neighbouring run (previous run preferred, the
    /// following run for a short leading run). Iterates to a fixed point so a
    /// short run between two equal runs collapses cleanly. A leg that is a
    /// single run is left untouched. Kills the speckle that raw per-edge
    /// coverage produces at junctions and from forward/return geometry
    /// mismatches.
    static func dissolveShortRuns(_ mult: inout [Double], lengths: [Double], minRun: Double) {
        let n = mult.count
        guard n > 1 else { return }
        var changed = true
        var iterations = 0
        while changed && iterations < n {
            changed = false
            iterations += 1
            var start = 0
            while start < n {
                var end = start
                while end + 1 < n && mult[end + 1] == mult[start] { end += 1 }
                let runLength = lengths[start ... end].reduce(0, +)
                let spansWholeLeg = (start == 0 && end == n - 1)
                if runLength < minRun && !spansWholeLeg {
                    let neighbor: Double = start > 0 ? mult[start - 1]
                        : (end + 1 < n ? mult[end + 1] : mult[start])
                    if neighbor != mult[start] {
                        for j in start ... end { mult[j] = neighbor }
                        changed = true
                    }
                }
                start = end + 1
            }
        }
    }
}
