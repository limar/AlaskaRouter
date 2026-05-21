// AlaskaRouter-9axu — segment-level route geometry with overlap detection.
//
// For multi-pass routes (out-and-back, loops with shared spurs, return legs),
// we don't want repeated road segments stacking on top of each other under
// the highlight. This module groups segments by their geographic road
// signature, then assigns each pass a perpendicular offset slot so multiple
// passes render as parallel ribbons.

import Foundation
import CoreLocation

/// One leg of the trip — from one waypoint to the next in route order.
struct TripSegment: Identifiable {
    let id: String                       // "<fromWp>→<toWp>"
    let fromWaypointID: UUID
    let toWaypointID: UUID
    /// Pre-offset polyline — already shifted perpendicular by the appropriate
    /// pass slot, so the renderer can hand this straight to MLNPolylineFeature.
    let coords: [CLLocationCoordinate2D]
    let color: TripColor
    let isExtraPass: Bool                // true if this is the 5th+ pass — render dashed
}

/// Perpendicular-offset a polyline by ~`offsetPt` pixels at a typical mid
/// zoom (~z=12). MapLibreSwiftDSL doesn't expose lineOffset, so we shift the
/// coordinates themselves. The offset is in coord-degrees, hand-tuned to
/// match ~1.5× core line width at z=10..12 (where users typically plan).
/// Slightly under-offset at low zoom and slightly over at very high zoom —
/// acceptable for the "two-cars-avoiding-each-other" feel the user asked for.
private func perpendicularOffset(_ coords: [CLLocationCoordinate2D], byPoints offset: Float) -> [CLLocationCoordinate2D] {
    guard coords.count >= 2, offset != 0 else { return coords }
    // ~7pt offset reads as ~1.5× core line width at zoom 10. The scaling
    // factor below is tuned so 7pt → ~0.0001° lat (~11 m on the ground at
    // 64° N) which renders to ~7 px at z=10. Tweak if visual is off.
    let offsetDeg = Double(offset) / 70_000.0
    var result: [CLLocationCoordinate2D] = []
    result.reserveCapacity(coords.count)
    for i in 0 ..< coords.count {
        let prev = (i > 0) ? coords[i - 1] : coords[i]
        let next = (i < coords.count - 1) ? coords[i + 1] : coords[i]
        let dLat = next.latitude - prev.latitude
        let dLon = next.longitude - prev.longitude
        let len = (dLat * dLat + dLon * dLon).squareRoot()
        guard len > 1e-9 else {
            result.append(coords[i])
            continue
        }
        // 90° CCW rotation of the tangent: (dLat, dLon) → (-dLon, dLat).
        // Approximate — doesn't compensate for the cos(latitude) lon-stretch
        // because at Alaska latitudes the visual error is small enough.
        let perpLat = -dLon / len * offsetDeg
        let perpLon =  dLat / len * offsetDeg
        result.append(.init(
            latitude: coords[i].latitude + perpLat,
            longitude: coords[i].longitude + perpLon
        ))
    }
    return result
}

extension Trip {

    /// Width unit for between-pass offsets. Each additional pass sits this
    /// many "units" away from its neighbor. Tuned for "subtle / two-cars-
    /// avoiding-each-other" feel per user spec.
    private static let passOffsetUnit: Float = 7.0
    private static let passOffsetCap: Float = 14.0   // ±2W
    private static let extraPassDashedAfterSlot: Int = 4

    /// Build the segment list with per-pass offsets. Falls back to straight-
    /// line geometry between waypoints when snapped coords aren't available.
    func passOffsetSegments(snappedCoords: [CLLocationCoordinate2D]?) -> [TripSegment] {
        let stops = orderedWaypoints
        guard stops.count >= 2 else { return [] }

        // Locate each waypoint's nearest index in the snapped polyline (or
        // use waypoint coords directly when no snap is available).
        let useSnap = (snappedCoords?.count ?? 0) >= 2
        let baseCoords = snappedCoords ?? stops.map(\.coordinate)
        let waypointIndexes: [Int] = {
            if useSnap {
                return stops.map { wp in
                    var bestIdx = 0
                    var bestDist = Double.infinity
                    for (i, c) in baseCoords.enumerated() {
                        let d = SmartInsert.haversine(c, wp.coordinate)
                        if d < bestDist { bestDist = d; bestIdx = i }
                    }
                    return bestIdx
                }
            } else {
                return Array(stops.indices)
            }
        }()

        // Build segments (one per stop pair).
        let blocksByWaypointID: [UUID: TripColor] = {
            var m: [UUID: TripColor] = [:]
            for b in self.blocks {
                for wp in b.waypoints { m[wp.id] = b.color }
            }
            return m
        }()

        struct RawSegment {
            let fromID: UUID
            let toID: UUID
            let coords: [CLLocationCoordinate2D]
            let color: TripColor
        }
        var raws: [RawSegment] = []
        for i in 0 ..< stops.count - 1 {
            let lo = min(waypointIndexes[i], waypointIndexes[i + 1])
            let hi = max(waypointIndexes[i], waypointIndexes[i + 1])
            guard hi > lo else { continue }
            let slice = Array(baseCoords[lo...hi])
            // Per the user's earlier spec, the road LEAVING block N's last
            // stop takes the COLOR of the next block (the segment "enters"
            // the new block). i.e. segment color = destination's block color.
            let color = blocksByWaypointID[stops[i + 1].id] ?? self.color
            raws.append(RawSegment(
                fromID: stops[i].id,
                toID: stops[i + 1].id,
                coords: slice,
                color: color
            ))
        }

        // Group by road signature (sorted set of quantized sample points —
        // direction-invariant so an out-and-back collapses to one group).
        let signatures = raws.map { signature(for: $0.coords) }
        var slotsPerSig: [String: Int] = [:]
        var groupSizes: [String: Int] = [:]
        for sig in signatures {
            groupSizes[sig, default: 0] += 1
        }

        // Assign each raw segment a 0-indexed slot within its group, then
        // turn that into a signed offset.
        var out: [TripSegment] = []
        for (raw, sig) in zip(raws, signatures) {
            let slot = slotsPerSig[sig, default: 0]
            slotsPerSig[sig] = slot + 1
            let total = groupSizes[sig] ?? 1

            let (offset, isExtra) = offsetForSlot(slot, total: total)
            let shiftedCoords = perpendicularOffset(raw.coords, byPoints: offset)
            out.append(TripSegment(
                id: "\(raw.fromID)→\(raw.toID)",
                fromWaypointID: raw.fromID,
                toWaypointID: raw.toID,
                coords: shiftedCoords,
                color: raw.color,
                isExtraPass: isExtra
            ))
        }
        return out
    }

    /// Compute the perpendicular offset (in points) for pass `slot` within a
    /// group of `total` passes. Returns (offset, isExtraPass).
    ///
    /// Distribution:
    ///   - total = 1 → centered (offset 0)
    ///   - total = 2 → ±(W/2)
    ///   - total = 3 → -W, 0, +W
    ///   - total = 4 → -1.5W, -0.5W, +0.5W, +1.5W
    ///   - total ≥ 5 → slots 0..3 spread normally; slots 4+ cap at ±2W and
    ///     are flagged as extra passes (rendered with a dash pattern by the
    ///     map view so they read as "extra passes on this slot").
    private func offsetForSlot(_ slot: Int, total: Int) -> (Float, Bool) {
        let W = Trip.passOffsetUnit
        if total <= 4 {
            let center = Float(total - 1) / 2.0
            return (W * (Float(slot) - center), false)
        }
        // total >= 5
        if slot < 4 {
            // First 4 passes spread as if total=4.
            return (W * (Float(slot) - 1.5), false)
        }
        // 5th+ pass — alternate at ±2W, dashed.
        let cap = Trip.passOffsetCap
        let sign: Float = (slot % 2 == 0) ? -1.0 : 1.0
        return (sign * cap, true)
    }

    /// Direction-invariant road signature for a polyline. Subsamples to a
    /// fixed budget, quantizes each lat/lon to a ~50 m grid, sorts and joins.
    /// Two segments hashing to the same signature are treated as the same road.
    private func signature(for coords: [CLLocationCoordinate2D]) -> String {
        guard !coords.isEmpty else { return "" }
        let budget = 12
        let n = coords.count
        var samples: [String] = []
        if n <= budget {
            samples.reserveCapacity(n)
            for c in coords { samples.append(quantize(c)) }
        } else {
            samples.reserveCapacity(budget)
            for i in 0 ..< budget {
                let idx = Int(Double(i) * Double(n - 1) / Double(budget - 1))
                samples.append(quantize(coords[idx]))
            }
        }
        return samples.sorted().joined(separator: "|")
    }

    /// ~50 m quantization grid. Lon-degree shrinks with latitude, but at our
    /// expedition latitudes (50–70°N) it stays within the same order of
    /// magnitude — close enough for "is this the same road" detection.
    private func quantize(_ c: CLLocationCoordinate2D) -> String {
        let qLat = Int((c.latitude * 2000).rounded())   // 1/2000° ≈ 56 m
        let qLon = Int((c.longitude * 2000).rounded())
        return "\(qLat),\(qLon)"
    }
}
