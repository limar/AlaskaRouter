// Compute the rendering-time blocks of a trip from its waypoints + user-placed
// BlockSeparators. A block is a contiguous run of stops sharing one color/name.
//
// No persistent Block @Model — blocks are derived at view time. This keeps the
// schema lean and makes reorder/insert/delete updates trivial (you mutate the
// underlying waypoints and separators; blocks re-derive automatically).

import Foundation
import CoreLocation

/// A non-persistent block for rendering. Each block owns its sequence of stops,
/// gets its color from the palette by block index, and its name from the first
/// and last stop labels.
struct TripBlock: Identifiable {
    /// Stable identity for SwiftUI — the id of the leading separator, or a
    /// fixed sentinel ("block-0") for the first block.
    let id: String
    let index: Int                  // 0-based block index in the trip
    let waypoints: [Waypoint]       // contiguous stops in this block, in route order
    /// nil for block 0. Subsequent blocks point at the separator that
    /// produced them. Block 0 isn't "implicit" — it's a full first-class
    /// block, just one without a separator above it by definition
    /// (AlaskaRouter-pufj).
    let leadingSeparator: BlockSeparator?
    let color: TripColor
    /// Auto-name: "First → Last", or just the single stop name if 1 stop.
    var displayName: String {
        guard let first = waypoints.first else { return "Block \(index + 1)" }
        if waypoints.count == 1 { return first.label ?? "Block \(index + 1)" }
        let last = waypoints.last!
        let f = first.label ?? "?"
        let l = last.label ?? "?"
        return "\(f) → \(l)"
    }
}

/// One row in the bottom-sheet's unified list. Stops and block headers
/// interleave. Every block — including block 0 — has a header row, even
/// though block 0 has no underlying `BlockSeparator` (pufj). The optional
/// `separator` distinguishes the cases:
///   - `separator: nil` — block 0's synthetic header; fixed at top,
///                        not reorderable, not deletable.
///   - `separator: .some` — a real separator the user inserted; movable,
///                          deletable, persists in SwiftData.
enum TripListItem: Identifiable {
    case stop(Waypoint)
    case blockHeader(separator: BlockSeparator?, blockIndex: Int, color: TripColor, displayName: String)

    /// Stable string ID across all items, prefixed so a separator's UUID
    /// can never collide with a waypoint's. Block 0's synthetic header
    /// uses the fixed `"block-0"` sentinel.
    var id: String {
        switch self {
        case .stop(let wp): return "stop-\(wp.id.uuidString)"
        case .blockHeader(let sep, let idx, _, _):
            if let sep = sep { return "sep-\(sep.id.uuidString)" }
            return "block-\(idx)"
        }
    }
}

extension Trip {

    /// Block palette rotation. Block 0 inherits the trip's own color; blocks
    /// 1..N rotate through the remaining TripColors so neighbors are distinct.
    private static let blockPaletteRotation: [TripColor] =
        [.amber, .teal, .terracotta, .sage, .indigo, .slate]

    /// Compute the rendering blocks. Every non-empty trip has at least one
    /// block — block 0 — which by definition has no separator above it.
    /// Every waypoint is in exactly one block; callers can rely on
    /// `blocksByWaypointID` lookups never missing (pufj invariant).
    var blocks: [TripBlock] {
        let stops = orderedWaypoints
        guard !stops.isEmpty else { return [] }

        // Map separators to the index of the waypoint they sit AFTER.
        let stopIndexByID = Dictionary(uniqueKeysWithValues: stops.enumerated().map { ($1.id, $0) })
        // Active separators = ones whose anchor still exists, sorted by the
        // anchor waypoint's position so blocks come out in route order. Two
        // separators anchored to the SAME stop describe one boundary, so we
        // collapse to the first per position — this keeps `blocks` total (it
        // must never crash on a stray duplicate left by an upstream edit; the
        // edit paths themselves dedupe so duplicates don't persist).
        var seenSplit = Set<Int>()
        let active: [(splitAfterIndex: Int, sep: BlockSeparator)] = separators.compactMap { s in
            guard let id = s.afterWaypointID, let idx = stopIndexByID[id] else { return nil }
            // Separator after the last stop is degenerate (no following stops).
            guard idx < stops.count - 1 else { return nil }
            return (idx, s)
        }
        .sorted { $0.splitAfterIndex < $1.splitAfterIndex }
        .filter { seenSplit.insert($0.splitAfterIndex).inserted }

        // Walk stops and slice into blocks at each boundary. A block's LEADING
        // separator is the boundary that BEGINS it (the previous split), not
        // the one that ends it; block 0 has none. Because `active` is sorted
        // and de-duplicated, each split is strictly greater than the previous,
        // so `startIdx <= endIdx` always holds.
        var result: [TripBlock] = []
        var startIdx = 0
        var leadingSep: BlockSeparator? = nil
        func emitBlock(endingAt endIdx: Int) {
            let idx = result.count
            result.append(TripBlock(
                id: leadingSep.map { $0.id.uuidString } ?? "block-0",
                index: idx,
                waypoints: Array(stops[startIdx ... endIdx]),
                leadingSeparator: leadingSep,
                color: colorForBlock(idx)
            ))
        }
        for (splitAfter, sep) in active {
            emitBlock(endingAt: splitAfter)
            startIdx = splitAfter + 1
            leadingSep = sep            // this separator BEGINS the next block
        }
        if startIdx <= stops.count - 1 {
            emitBlock(endingAt: stops.count - 1)
        }
        return result
    }

    /// The flat list of rows the bottom sheet should render (block headers
    /// + stops). Order: for each block, a header row, then the block's stops.
    /// Every block produces a header — block 0's header is synthetic
    /// (`separator: nil`) because there's no preceding separator by
    /// definition (pufj).
    var listItems: [TripListItem] {
        var out: [TripListItem] = []
        for b in blocks {
            out.append(.blockHeader(
                separator: b.leadingSeparator,
                blockIndex: b.index,
                color: b.color,
                displayName: b.displayName
            ))
            for wp in b.waypoints {
                out.append(.stop(wp))
            }
        }
        return out
    }

    private func colorForBlock(_ idx: Int) -> TripColor {
        if idx == 0 { return color }
        let pool = Trip.blockPaletteRotation.filter { $0 != color }
        return pool[(idx - 1) % pool.count]
    }
}
