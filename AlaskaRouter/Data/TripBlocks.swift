// Compute the rendering-time blocks of a trip from its waypoints + user-placed
// BlockSeparators. A block is a contiguous run of stops sharing one color/name.
//
// No persistent Block @Model — blocks are derived at view time. This keeps the
// schema lean and makes reorder/insert/delete updates trivial (you mutate the
// underlying waypoints and separators; blocks re-derive automatically).

import Foundation

/// A non-persistent block for rendering. Each block owns its sequence of stops,
/// gets its color from the palette by block index, and its name from the first
/// and last stop labels.
struct TripBlock: Identifiable {
    /// Stable identity for SwiftUI — the id of the leading separator, or a
    /// fixed sentinel for the implicit first block.
    let id: String
    let index: Int                  // 0-based block index in the trip
    let waypoints: [Waypoint]       // contiguous stops in this block, in route order
    let leadingSeparator: BlockSeparator?  // nil for the implicit first block
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

/// One row in the bottom-sheet's unified list. Stops and separators interleave.
enum TripListItem: Identifiable {
    case stop(Waypoint)
    case separator(BlockSeparator, blockIndex: Int, color: TripColor, displayName: String)

    var id: UUID {
        switch self {
        case .stop(let wp): return wp.id
        case .separator(let s, _, _, _): return s.id
        }
    }
}

extension Trip {

    /// Block palette rotation. Block 0 inherits the trip's own color; blocks
    /// 1..N rotate through the remaining TripColors so neighbors are distinct.
    private static let blockPaletteRotation: [TripColor] =
        [.amber, .teal, .terracotta, .sage, .indigo, .slate]

    /// Compute the rendering blocks. Always returns at least one (the implicit
    /// first block containing every stop if the trip has no separators).
    var blocks: [TripBlock] {
        let stops = orderedWaypoints
        guard !stops.isEmpty else { return [] }

        // Map separators to the index of the waypoint they sit AFTER.
        let stopIndexByID = Dictionary(uniqueKeysWithValues: stops.enumerated().map { ($1.id, $0) })
        // Active separators = ones whose anchor still exists. Sort by the
        // anchor waypoint's position so blocks come out in route order.
        let active: [(splitAfterIndex: Int, sep: BlockSeparator)] = separators.compactMap { s in
            guard let id = s.afterWaypointID, let idx = stopIndexByID[id] else { return nil }
            // Separator after the last stop is degenerate (no following stops).
            guard idx < stops.count - 1 else { return nil }
            return (idx, s)
        }
        .sorted { $0.splitAfterIndex < $1.splitAfterIndex }

        // Walk stops and slice into blocks at each separator boundary.
        var result: [TripBlock] = []
        var startIdx = 0
        var blockIndex = 0
        for (splitAfter, sep) in active {
            let segment = Array(stops[startIdx...splitAfter])
            let color = colorForBlock(blockIndex)
            result.append(TripBlock(
                id: blockIndex == 0 ? "block-0" : sep.id.uuidString,
                index: blockIndex,
                waypoints: segment,
                leadingSeparator: blockIndex == 0 ? nil : sep,
                color: color
            ))
            startIdx = splitAfter + 1
            blockIndex += 1
        }
        // Final tail block.
        if startIdx <= stops.count - 1 {
            let segment = Array(stops[startIdx...(stops.count - 1)])
            // The leading separator is the LAST one (sits before this block).
            let leadSep = blockIndex == 0 ? nil : active.last?.sep
            result.append(TripBlock(
                id: blockIndex == 0 ? "block-0" : (leadSep?.id.uuidString ?? "block-\(blockIndex)"),
                index: blockIndex,
                waypoints: segment,
                leadingSeparator: leadSep,
                color: colorForBlock(blockIndex)
            ))
        }
        return result
    }

    /// The flat list of rows the bottom sheet should render (stops + separators).
    /// Order: for each block, the leading separator (if any) then the block's stops.
    var listItems: [TripListItem] {
        var out: [TripListItem] = []
        for b in blocks {
            if let sep = b.leadingSeparator {
                out.append(.separator(sep, blockIndex: b.index, color: b.color, displayName: b.displayName))
            }
            for wp in b.waypoints {
                out.append(.stop(wp))
            }
        }
        return out
    }

    /// True when there are 2+ blocks (i.e. any separator survived). Single-block
    /// trips render in one color (no per-block coloring on the map).
    var isMultiBlock: Bool { blocks.count >= 2 }

    private func colorForBlock(_ idx: Int) -> TripColor {
        if idx == 0 { return color }
        let pool = Trip.blockPaletteRotation.filter { $0 != color }
        return pool[(idx - 1) % pool.count]
    }
}
