---
# AlaskaRouter-tiiz
title: 'Bug: crash when reordering waypoints in the bottom sheet'
status: completed
type: bug
priority: high
created_at: 2026-05-29T16:18:10Z
updated_at: 2026-05-29T16:56:07Z
---

Reordering (drag-to-move) waypoints in the trip bottom sheet crashes the app; Xcode stops in lldb.

## Repro
Moving waypoints around in the bottom sheet list. Exact gesture + backtrace to be captured from the lldb session.

## Investigation
- [x] Capture crash message + backtrace from lldb
- [x] Identify the failing call site
- [x] Root-cause
- [x] Fix + add regression test
- [x] Verify on simulator

## Notes
Branch claude/ecstatic-bouman-ed317a, based on 84670ab. Related history: "Fix stop renumbering after middle deletion" (75a4105).

## Crash
`Fatal error: Range requires lowerBound <= upperBound` at TripBlocks.swift:94 in `Trip.blocks.getter`, hit via `routeRibbons`→`self.blocks` during map re-render after a reorder. Plus a SwiftUI warning: separator id occurs multiple times in the list.

## Root cause (two bugs, both in the block model, exposed by reorder)
1. **reorderListItems re-anchors every separator to the preceding stop.** If a reorder leaves two block headers adjacent (no stop between — e.g. dragging a stop out from between two blocks, or dropping a header beside another), BOTH separators get `afterWaypointID = <same stop>`. Then `Trip.blocks` slices `stops[startIdx...splitAfter]` and the 2nd duplicate gives startIdx > splitAfter → range crash. The bad separator set is saved, so the trip can crash on every subsequent render.
2. **Trip.blocks off-by-one:** it assigns each block the separator at its END rather than the one that BEGINS it, so for 3+ blocks the last separator is duplicated across two blocks → the duplicate-ID warning + wrong leadingSeparator (delete/move targets the wrong separator).
Also: `pruneDegenerateSeparators` deletes while iterating `trip.separators` (snapshot it).

## Fix plan (root-cause)
- [x] reorderListItems: never anchor two separators to the same stop — delete the redundant one (empty block is meaningless).
- [x] pruneDegenerateSeparators: also drop duplicate-anchor separators; iterate a snapshot → heals the already-corrupted trip on next edit.
- [x] Trip.blocks: fix off-by-one (leadingSeparator = boundary that BEGINS the block) and collapse duplicate boundaries so the getter is total (lets the currently-corrupt trip render again immediately).
- [x] Unit tests at model level (blocks): 3-block leadingSeparators distinct/correct; duplicate-anchor separators don't crash. DONE — 14/14 DataInvariantTests pass.
- [x] Verify on simulator (reproduce the reorder, confirm no crash + correct blocks). Confirmed by user: works.

## Summary of Changes
Reordering waypoints could anchor two block separators to the same stop, making `Trip.blocks` slice an inverted range and crash ("Range requires lowerBound <= upperBound"); the corrupt set was persisted so the trip then crashed on every render. Fixed at the source: reorderListItems never double-anchors (deletes the redundant empty-block separator); pruneDegenerateSeparators drops duplicate-anchor separators and snapshots the array (heals corrupted trips); Trip.blocks fixes an off-by-one (leadingSeparator = the boundary that BEGINS the block, killing the duplicate-id ForEach warning on 3+ block trips) and collapses duplicate boundaries so the getter is total. Tests: DataInvariantTests 14/14. Verified on-device by user.
