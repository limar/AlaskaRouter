---
# AlaskaRouter-ucyl
title: Inline 'split here' per stop row; retire the bottom Add-separator row
status: todo
type: feature
priority: high
created_at: 2026-05-30T09:08:36Z
updated_at: 2026-07-27T22:41:47Z
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

- [ ] Where exactly on the row does the split control sit, and is it always visible or revealed (swipe / long press / edit mode)? Always-visible icons on 54 rows is a lot of visual noise — the whole reason we deviated from the mock.
- [ ] Does the bottom "Add block separator" row go away entirely, or stay as the "append a block at the end" path?
- [ ] Split *above* this stop or *below* it? The mock says "start a new block at this stop" (above); the current separator model is `afterWaypointID` (below).
- [ ] Interaction with the existing swipe-to-remove on stop rows (AlaskaRouter-24t5) — do split and remove share one swipe tray?

## Todo
- [ ] Render variants over the real 54-stop trip (not a 5-stop demo — density is the whole problem), light + dark
- [ ] Agree placement and reveal behaviour
- [ ] Implement; drop the fixed `stops.count - 2` anchor
- [ ] Verify on the real Alaska trip: create a day break at stop 7 without scrolling gymnastics
