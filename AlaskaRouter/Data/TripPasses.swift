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

/// One ribbon — a maximal run of consecutive legs within a pass that
/// belong to the same block (and therefore share a color). One pass that
/// crosses N blocks emits N ribbons, all at the same offset, meeting at
/// block-boundary waypoints. Ready for the renderer to drop straight into
/// a single MLNLineStyleLayer with native lineOffset.
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
    ///   - single pass             → 0      (no offset, centered)
    ///   - 1st lane, left          → -0.5   (rank 0)
    ///   - 2nd lane, left          → -1.5   (rank 1)
    ///   - nth lane, left          → -(rank + 0.5)
    /// Negative in MapLibre's convention means "left of travel direction";
    /// opposite-direction passes therefore land on opposite absolute sides.
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
    /// Step 1 — identify passes (maximal runs of consecutive legs with no
    /// direction reversal). Out-and-back = 2 passes. Forward only = 1.
    ///
    /// Step 2 — within each pass, split at every block boundary so each
    /// emitted ribbon is one polyline + one block color + one offset.
    /// All ribbons of one pass share the same offset, so a multi-block
    /// pass renders as visually-continuous segments that just change
    /// color at each block boundary.
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

        // 4. Resolve color per leg from the block model. The road LEAVING
        //    block N's last stop takes block N+1's color (segment "enters"
        //    the new block) — matches the rest of TripBlocks's convention.
        let blocksByWaypointID: [UUID: TripColor] = {
            var m: [UUID: TripColor] = [:]
            for b in self.blocks {
                for wp in b.waypoints { m[wp.id] = b.color }
            }
            return m
        }()

        // 5. For each pass, walk its legs and split into ribbons at every
        //    block-color boundary. Each ribbon = one polyline + one color
        //    + the pass's offset. Multi-block passes emit multiple
        //    ribbons that meet at the boundary waypoint (continuous in
        //    the visual lane, just changing color).
        let multiPass = descriptors.count >= 2
        var out: [RouteRibbon] = []
        var ribbonIdx = 0

        for d in descriptors {
            // Offset for this whole pass.
            let multiplier: Double = multiPass ? -(Double(d.rank) + 0.5) : 0

            // Walk legs in pass order, grouping by color.
            var curCoords: [CLLocationCoordinate2D] = []
            var curColor: TripColor? = nil
            func flushCurrent() {
                guard !curCoords.isEmpty, let color = curColor else { return }
                out.append(RouteRibbon(
                    id: ribbonIdx,
                    coords: curCoords,
                    offsetMultiplier: multiplier,
                    color: color,
                    isStraightLineFallback: !useSnap
                ))
                ribbonIdx += 1
                curCoords = []
                curColor = nil
            }

            for legIdx in d.legIndices {
                let leg = legs[legIdx]
                let destID = stops[leg.endStop].id
                let legColor = blocksByWaypointID[destID] ?? self.color

                // Pull this leg's coord slice from the base polyline.
                let s = waypointIndexes[leg.startStop]
                let e = waypointIndexes[leg.endStop]
                let lo = min(s, e)
                let hi = max(s, e)
                guard hi > lo else { continue }
                var legCoords = Array(baseCoords[lo...hi])
                if s > e { legCoords.reverse() }

                if curColor == nil {
                    curColor = legColor
                    curCoords = legCoords
                } else if curColor == legColor {
                    // Same color → extend ribbon. Drop duplicate join point.
                    curCoords.append(contentsOf: legCoords.dropFirst())
                } else {
                    // Color change → flush this ribbon, start new one.
                    flushCurrent()
                    curColor = legColor
                    curCoords = legCoords
                }
            }
            flushCurrent()
        }
        return out
    }
}
