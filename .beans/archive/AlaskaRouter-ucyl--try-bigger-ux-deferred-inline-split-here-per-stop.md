---
# AlaskaRouter-ucyl
title: Inline 'split here' per stop row; retire the bottom Add-separator row
status: completed
type: feature
priority: high
created_at: 2026-05-30T09:08:36Z
updated_at: 2026-07-27T23:10:47Z
parent: AlaskaRouter-36of
---

Mock has a small 'split here' button per stop row (contextual start-a-new-block-at-this-stop). Replaces the bottom 'Add block separator' row with contextual action. Bigger UX change than the styling round — leave for after the visual cleanup lands.

## Un-scrapped — the field settled it (2026-07-27)

Reopened and pulled into **AlaskaRouter-36of (v1.1 — Field Fixes)**. This was scrapped as "bigger UX, deferred"; the Alaska trip produced strongly negative feedback on the shipped alternative, so it is now sprint work.

## What the field found

With a 54-stop trip, the single bottom "Add block separator" row means every new separator is born at the wrong end of the list and has to be dragged all the way up — "finger acrobatics", fighting the list's own scrolling the whole way.

It is worse than just the button's placement. `addBlockSeparator` (`TripBottomSheet.swift:1010`) hard-codes the insertion point:

```swift
// Place the new separator AFTER the second-to-last stop so block 2
// visibly contains the last stop.
let anchor = stops[stops.count - 2]
```

So the separator always appears near the **end** of the trip no matter where the user actually wants the day to break. On a 5-stop demo trip that is a short drag; on the real 54-stop trip it is unusable.

## The mock had it right

`design/mocks/README.md:71-72`:
> Each stop row: drag handle · numbered pip in block color · POI name (serif) · **split button (start new block here)** · remove button.
> Tap the split icon next to any stop to start a new block at that stop.

`design/mocks/sheet.jsx:497` — "Inline actions: split here (start new block above this stop) + remove".

Note the mock also puts **remove** on the stop row, which overlaps with AlaskaRouter-pmnd (callout Remove button is too loud / in the wrong slot). The two should be designed in one pass — if remove lives on the row, the callout may not need it at all.

## Open design questions (discuss before implementing)

- [x] Not on the row at all — on the connector BETWEEN stops, always visible, icon only.
- [x] Gone entirely — every gap now has its own control, so it had nothing left to do.
- [x] Above — `splitBlock(before:)` anchors to the preceding stop, so the tapped stop starts the new block.
- [x] No — they stay separate. A shared tray was built and rejected (it slid the row name off-screen).

## Todo
- [x] Rendered four variants over the real 41-stop trip
- [x] Agreed: icon on the connector, always visible
- [x] Implement; drop the fixed `stops.count - 2` anchor
- [x] Verified on the real Alaska trip: split lands exactly where tapped

## Summary of Changes

Split control now sits **on the connector between two stops**, icon-only — chosen from four rendered variants over the real 41-stop trip.

Why this one:
- A separator *is* the gap, not a property of a stop, so the connector is where it belongs semantically.
- It reuses the existing leg band, so the resting list is barely changed — no second icon on 41 rows.
- Stop names keep their full width. The mock-literal per-row variant truncated "Galbraith Lake Campground", which is what made us deviate from the mock originally.

Rejected, with reasons:
- **Labelled "Split here" on the connector** — clearest, but repeated across ~40 legs it competes with the distance capsules; the list gets busier the longer the trip.
- **Icon on every stop row (the mock)** — truncates names, noisiest.
- **Split inside the swipe tray next to Delete** — zero resting chrome, but the 168 pt tray slides the row name entirely off-screen so you cannot see which stop you are cutting at, and it is undiscoverable.

Implementation notes:
- `splitBlock(before:)` anchors the separator to the *preceding* stop, so the block breaks exactly where the user tapped. The old `addBlockSeparator` hard-coded `stops.count - 2` — the root cause of the field complaint.
- The connector band now renders for **every** incoming leg, not just ones with a known distance; an unrouted leg is still a gap you can break the day at.
- `hasSeparatorBefore(_:)` hides the control where a separator already occupies the gap, so there are no dead controls.
- The glyph is deliberately small, but the hit shape is padded to 60×34 pt so the target is comfortable — the visible size and the tappable size are decoupled.
- The bottom "Add block separator" row and `addBlockSeparator()` are **deleted**. Its only behaviour was the one being complained about. Flagged to the user as a judgement call.

**Verified on the real 41-stop Alaska trip:** tapped the scissors in the 95 km gap between Yukon River Camp and Arctic Circle; a new block "Arctic Circle → Coldfoot Camp" appeared at exactly that point, blocks renumbered, and the scissors vanished from that gap since it is now a boundary. No dragging.
