---
# AlaskaRouter-pmnd
title: Callout "Remove" is too loud and sits where "Add" sits
status: completed
type: task
priority: high
created_at: 2026-07-27T21:34:45Z
updated_at: 2026-07-27T23:10:47Z
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
- [x] Rendered the variants side by side over the actual map
- [x] Picked: Share promoted to the primary slot, Remove in a header “…” menu
- [x] Implement; keep PreviewCallout and StopCallout coherent with each other

## Summary of Changes

The primary action slot now holds **"Open in…"**, and Remove moved into a **"…" menu in the callout header**.

Both complaints are addressed: removal is no longer the loudest thing in the callout, and it no longer occupies the slot where `PreviewCallout` puts the constructive "Add to trip" — that slot now holds a constructive action here too, so the spatial grammar reads consistently instead of inverted.

Rejected, with reasons:
- **Remove in the menu, action row left empty** — leaves a lone Share icon floating beside dead space; reads as unfinished.
- **Drop Remove from the callout entirely** — defensible (the stop row already has a minus button and swipe-to-delete, which is where the mock put removal), but it means removing a stop you are looking at on the map requires finding it in the sheet first.

One cost found in the render and fixed: the header "…" eats into the title's width, and at the old 260 pt max the stop name *and* the "170 km from …" line both started truncating. Callout widened 260 → 300 (still under `PreviewCallout`'s 320), which restores the distance line in full and leaves the title truncating no worse than before.

The header menu is also the natural home for Rename / Move-to-block when those arrive (AlaskaRouter-mhax).
