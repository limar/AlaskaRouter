---
# AlaskaRouter-pmnd
title: Callout "Remove" is too loud and sits where "Add" sits
status: todo
type: task
priority: high
created_at: 2026-07-27T21:34:45Z
updated_at: 2026-07-27T21:36:47Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. Two problems with one button.

1. **Too prominent.** The big red capsule is the first thing the eye lands on in a waystop callout. Removal is a *rare* operation; it should not be the visual centre of gravity.
2. **Occupies the opposite action's slot.** `PreviewCallout` puts "+ Add to trip" in the left slot; `StopCallout` puts "Remove" in the same left slot. This was a deliberate "left = trip-membership" grammar (see the comments at `StopCallout.swift:20-25` and `PreviewCallout.swift:59-63`), and the field verdict is that it reads wrong: muscle memory says "the big left button is the safe/constructive one", and here it destroys.

## Files
- `AlaskaRouter/UI/StopCallout.swift:91-112` — the Remove capsule + Share button row
- `AlaskaRouter/UI/PreviewCallout.swift:64-80` — the mirror "Add to trip" row
- Note `AlaskaRouter-24t5` already shipped swipe-to-delete on bottom-sheet stop rows, so the callout is **not** the only removal path.

## Options to mock and judge (visual proof required before any code)
- **(a) Overflow menu.** Remove moves into a "…" menu in the callout header next to the ✕. Left slot loses its button entirely, or gains a genuinely useful positive action. Matches Apple/Google. Leaves room for future Rename / Move-to-block.
- **(b) Demote to an icon.** Remove becomes a small trash icon button on the trailing edge, Share keeps its slot, left slot goes away.
- **(c) Keep the slot, drop the shout.** Same position, but neutral styling (no red fill, no border) — red reserved for the confirmation.
- **(d) Drop it from the callout.** Removal lives only in the bottom sheet (swipe), which already works.

Recommendation to beat: **(a)**, because it fixes both complaints at once and opens the header for the per-stop actions still parked under AlaskaRouter-mhax.

Also decide: does removal need a confirm step, or is the existing undo path enough?

## Todo
- [ ] Render the variants side by side (real screenshots over the actual map, light + dark)
- [ ] Pick one
- [ ] Implement; keep PreviewCallout and StopCallout coherent with each other
