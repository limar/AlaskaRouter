---
# AlaskaRouter-ucyl
title: Inline 'split here' per stop row; retire the bottom Add-separator row
status: completed
type: feature
priority: high
created_at: 2026-05-30T09:08:36Z
updated_at: 2026-07-27T23:56:55Z
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

## Reopened — the scissors affordance is rejected (2026-07-27)

User verdict on the shipped connector control, three separate objections:

1. **"Hardly divisable"** — too low-contrast to find. The glyph is 8.5 pt inside a dashed hairline capsule in `textMuted`; it disappears against the sheet.
2. **"Non-intuitive place"** — the connector position, which I argued was semantically correct, does not read as an actionable place to the user.
3. **Wrong metaphor** — "the meaning of scissors is reserved to *cut*, not *separate*." Cutting implies severing the route; what actually happens is a day boundary being inserted. The glyph promises the wrong outcome.

Objection 3 is the sharpest and probably explains 2: if the icon reads as "cut the route here", then putting it *on* the route line makes it look like it will sever the line. The placement and the glyph were reinforcing each other's wrong reading.

**What stays:** `splitBlock(before:)` and the removal of the `stops.count - 2` anchor are not in question — the separator landing where the user asks is the actual fix and it works. This is purely about the affordance.

## Directions for round 2

Reframe from "cut" to **"start a new block / day here"** — an additive act, not a destructive one. That suggests `+` over any blade, and a label doing the work rather than a glyph alone.

- **Labelled pill in the gap** — `+ New block`, at real contrast, not a whisper. Fixes 1 and 3; 2 only if the label carries it.
- **A full-width dashed insert line** across the gap with a centred `+`, echoing the block-header strip it creates. Very literal: "a divider goes here". Most visible; costs vertical rhythm.
- **Per-row trailing `+` with a block glyph** (e.g. `rectangle.split.1x2`) — back on the row, but additive and unambiguous. Costs the name width that made us reject it the first time.
- **From the block header** — "split this block" in a header menu, choosing the stop. No per-row chrome at all; least direct.

Note: the earlier round measured *noise* and picked the quietest thing that worked. The field says it went too quiet. Round 2 should bias toward legibility and hold noise as the constraint, not the objective.

## Todo
- [x] Render round-2 variants over the real 41-stop trip, biased toward legibility
- [x] Agree glyph + wording + placement
- [x] Implement; keep splitBlock(before:) as-is

## Round 2 — shipped

**Chosen: the labelled pill on the connector, reading "＋ Split here".** Same position as the rejected round-1 scissors, with the two real faults fixed — a tinted pill at proper contrast so it reads as a control, and a `+` saying something is being added rather than severed.

Rejected in round 2:
- **Dashed insert rule across the gap** — the most legible, and it previews the block-header strip it creates, but it added ~9 pt to every gap and its dashed rules competed visually with the real block headers ("which of these is the actual boundary?").
- **Split glyph on the stop row** — unambiguously actionable, since it joins the existing control column beside the minus, but `rectangle.split.1x2` is opaque without a label and it eats stop-name width.
- **Long-press the gap, nothing visible** — quietest possible and consistent with the map's long-press-to-drop-pin, but its only risk is discoverability, which a render cannot settle, so it was not built.

Wording: user chose **"Split here"** over "New block" and "New day". Noted tension, not blocking: "split" is the same verb family as the rejected scissors, so the `+` glyph is carrying the additive framing on its own. Easy to revisit if it reads wrong in the field.

**A process failure worth recording:** rounds 1 and 2's first pass were judged *blind* — the renders were read into the assistant's context but never sent to the user, so the earlier picks were made from prose descriptions alone. That is almost certainly why round 1 shipped something the field immediately rejected. Fixed, and captured as a memory.
