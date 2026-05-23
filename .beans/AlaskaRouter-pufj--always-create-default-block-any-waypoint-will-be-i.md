---
# AlaskaRouter-pufj
title: Always create default block. Any waypoint will be inside some block.
status: in-progress
type: task
priority: high
created_at: 2026-05-21T15:06:48Z
updated_at: 2026-05-23T17:38:46Z
parent: AlaskaRouter-xtua
---

## Plan

The data model is already correct: \`trip.blocks\` always returns ≥1 block for any non-empty trip, and the implicit first block is a real block (with a real color, derived from the trip's color). Every waypoint is *already* inside some block.

What's NOT correct: a defensive \`fallbackColor\` path in \`ExpeditionMapView.syncTripMarkerGroup\` that bypasses the per-block color when the lookup misses. Since the lookup never legitimately misses (every waypoint is in some block), this path obscures intent and hides bugs.

### Changes

- **\`ExpeditionMapView.swift\`** — drop the \`fallbackColor: TripColor\` parameter from \`syncTripMarkerGroup\`. Drop the \`?? fallbackColor\` in the color lookup. Add an \`assertionFailure\` in DEBUG when a waypoint isn't in \`blocksByWaypointID\` so future schema bugs surface loudly rather than silently rendering the trip color.
- **\`TripBlocks.swift\`** — update the \"implicit first block\" comments to make it clear block 0 is a full first-class block (just one without a preceding separator, by definition).

### Out of scope

- Adding a visible \"header card\" for block 0 in the bottom sheet (separate UX question — the trip name at the top of the sheet already plays that role).
- Allowing block 0 to be user-renamed (separate feature, requires a name field on a persistent block model — bigger schema change).

### Checklist

- [x] Drop fallbackColor from ExpeditionMapView.syncMarkerLayers + syncTripMarkerGroup
- [x] Replace fallback with DEBUG assert (silent amber in release so a marker still draws)
- [x] Update TripBlocks + TripBottomSheet comments to drop the "implicit first block" framing
- [ ] Build, verify trip still renders correctly with per-block coloring (on-device check)


## Summary of Changes

`ExpeditionMapView.syncTripMarkerGroup` no longer accepts a `fallbackColor`. The per-waypoint block lookup is now unconditional — if it ever misses, that's a schema-invariant violation surfaced via `assertionFailure` in DEBUG. (Release still draws something — falls back to amber silently — so a bug never produces an invisible marker.)

`TripBlocks.swift` and `TripBottomSheet.swift` had comments calling the first block "implicit" — updated to clarify it's a full first-class block, just one without a leading separator by definition.

No schema changes. No data-model changes. Pure code-cleanup that bakes in the invariant the data model already enforced.



## 2026-05-23 — declined, fix incomplete

User feedback: "I create a Trip. Add Fairbanks. It's show orphaned, not included in a block."

I mis-read the bean as a code-cleanup task. The actual requirement is **UX**: every waypoint should appear *visually* inside a block in the bottom sheet — including the first waypoint of a fresh trip. Today block 0 has no separator → `listItems` renders no header card above its stops → the user sees a floating waypoint with no block context.

Re-opening to fix properly: render a virtual block-0 header card in the bottom sheet's list so block 0 reads as a real block.


## 2026-05-23 — proper fix (UX, not just code-cleanup)

The user's actual ask: every waypoint should *visually* appear inside a block in the bottom sheet — including a fresh trip with a single waypoint. Previously block 0 had no header row in `listItems`, so users saw their first stop floating with no block context.

### What changed

`TripListItem` enum (`Data/TripBlocks.swift`):
- Renamed `.separator(BlockSeparator, …)` → `.blockHeader(separator: BlockSeparator?, …)`. The separator is now optional.
- Changed `id` type from `UUID` → `String`, prefixed by kind (`stop-{uuid}`, `sep-{uuid}`, `block-0`) so synthetic IDs can't collide with persistent ones.

`Trip.listItems`:
- Always emits a header row for every block, including block 0 (with `separator: nil`).

`TripBottomSheet`:
- `row(for:)` reads the synthetic-vs-real flag, applies `.moveDisabled` and `.deleteDisabled` to the synthetic block-0 header so it stays pinned at the top and can't be swiped away.
- `blockHeaderRow` hides the drag-handle icon for synthetic headers.
- Reorder/delete handlers updated for the new case shape; synthetic headers no-op safely.

### Behavior

- Single-waypoint trip (e.g. just Fairbanks): header card "1 ▸ Fairbanks ▸ 1 stop" at the top of the sheet, then the stop row beneath. No more orphan.
- Multi-stop, no separators: header card "1 ▸ Anchorage → Fairbanks ▸ N stops", then all stops.
- After inserting a separator: block 0 header for stops up to the split, then a regular separator-anchored header for block 1+.

### Checklist

- [x] `TripListItem`: introduce synthetic block-0 header (separator-optional)
- [x] `Trip.listItems`: always emit a header for block 0
- [x] `TripBottomSheet.row(for:)`: handle the synthetic case
- [x] Block-0 header is fixed (move + delete disabled, drag handle hidden)
- [x] Reorder / delete handlers skip the synthetic case
- [ ] Verify on device: single-waypoint trip shows a block header
- [ ] Verify on device: separators still work (reorder, delete) for blocks 1+
