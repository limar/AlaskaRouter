---
# AlaskaRouter-5430
title: Accidental waypoint dragging when scrolling the stop list
status: completed
type: bug
priority: high
created_at: 2026-07-27T23:28:04Z
updated_at: 2026-07-28T00:44:25Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. Scrolling the stop list frequently picks up a waypoint and starts a reorder instead of scrolling. On a 41-stop trip in a moving vehicle this is easy to do and quietly corrupts the itinerary.

## Desired
Drag starts **only** from the 6-dot handle on the leading edge. Touching the stop's name/body should scroll (or select), never begin a drag.

## The catch — this is not a one-liner
The list uses SwiftUI `List` + `.onMove(perform: reorderListItems)` (`TripBottomSheet.swift`). Outside edit mode, `.onMove` binds the long-press-drag to the **entire row**; SwiftUI exposes no API to restrict the grab to a subview. The 6-dot handle (AlaskaRouter-zvhr) is currently decorative — it *looks* like the grab point but isn't one.

Options, all with costs:
- **`.moveDisabled(true)` on rows + a custom drag** driven by a `DragGesture` on the handle, repositioning via the existing `reorderListItems` logic. Full control, and the handle finally means what it looks like. Cost: hand-rolled autoscroll-at-edges and drop-target maths, which is exactly the fiddly part `List` was giving us for free.
- **`.draggable` / `dropDestination`** on the handle only. More idiomatic, but reorder-within-a-list via drag-and-drop has its own rough edges and would need the same drop-index maths.
- **An explicit edit mode** — a "Reorder" toggle in the sheet header; rows only become draggable inside it. Cheapest and safest, and it also protects against accidental reorder entirely. Cost: a mode, and an extra tap before an intentional reorder.

Note AlaskaRouter-x5ss / AlaskaRouter-io69 were scrapped after fighting `List`'s reorder animations, so there is prior evidence that going custom here is a real project rather than a tweak. Worth a spike before committing.

Also relevant: an accidental reorder is currently silent and unlimited-undo-less. Whatever path is chosen, consider whether reorder should be undoable.

## Todo
- [x] Spike: yes — a high-priority long press on the row body does it
- [x] Neither was needed — see below
- [x] Implemented and verified on the 41-stop list

## Spike result — no custom drag, no edit mode needed

`.highPriorityGesture(LongPressGesture(minimumDuration: 0.25))` on the row **body** starves `List`'s internal reorder recognizer of the long press it waits for. The 6-dot handle is left uncovered, so it becomes the only place a drag can start — which is what the handle looked like it meant all along (it had been purely decorative since AlaskaRouter-zvhr).

Applied to both stop rows and block-header rows (separators are draggable too, and carry the same accidental-move risk).

**`highPriorityGesture` is load-bearing.** A plain `.onLongPressGesture` only *competes* with List's recognizer and loses — see the correction below. `List` + `.onMove` and the `.moveDisabled` calls stay exactly as they were, so all of List's reorder animation and drop-index maths is still doing the work. No hand-rolled drag, no `EditMode`.

`EditMode` was the other candidate — the only *native* mechanism that restricts dragging to a grabber — and was never needed. It would have imposed the system's own trailing grabber and leading delete circles on rows carefully designed not to have them.

### Verified on the 41-stop trip (injected input)
| behaviour | result |
|---|---|
| long-press-drag the row body | no reorder; order byte-identical before/after |
| long-press-drag the handle | reorders correctly |
| tap the row | still selects; map flies to the stop |
| drag-scroll the list | scrolls stops 1-6 → 7-13, no reorder |

### Correction — a false negative I initially reported as success

The first attempt used a plain `.onLongPressGesture`, and I reported it working. It was not. The test dragged the only stop in a single-stop block, so the drop resolved back to the same index and nothing appeared to move. Re-testing on a multi-stop block showed the row being picked up from the body exactly as before.

Lesson for this kind of verification: **assert on the full before/after order, and never drag the only element in its group** — a no-op drop is indistinguishable from a blocked drag.

### Note
The Simulator's seeded "Alaska" trip got shuffled during this testing. Simulator state only; the device copy is untouched.

## Follow-up: could the handle drag start on a *short* press?

Asked after the fix landed — with accidental drags eliminated, the long press is protection against a risk that no longer exists, so it is now pure friction on an intentional action. Investigated and **decided to keep the long press.**

**There is no public API to tune the reorder activation delay.** Searched the iOS 26 SwiftUI interface: nothing for reorder timing or drag activation. `List` + `.onMove` outside edit mode always waits for the system long press.

The only built-in route to an immediate drag is `EditMode`. Probed it directly, and both halves confirmed on device:
- It **does** drag on touch-down with no hold.
- It forces the system's own chrome: red delete circles on the leading edge, the `≡` grabber on the trailing edge, our 6-dot handle *and* our minus button both made redundant, and stop names truncating. **Four controls per row** on a design built for two.

Adopting it would mean re-doing the row — dropping the 6-dot handle (AlaskaRouter-zvhr) for the system grabber and the minus button (AlaskaRouter-0rh9) for the system delete circle — a design decision, not a tweak. Probe reverted; tree verified clean.

Rejected alternatives:
- **A "Reorder" mode toggle** — EditMode only while explicitly on, keeping the resting list clean. Viable, but costs a mode and an extra tap to reorder.
- **Custom drag on the handle** — immediate, design untouched, but hand-rolls edge autoscroll, drop-target maths and reorder animation. AlaskaRouter-x5ss and AlaskaRouter-io69 were both scrapped fighting exactly that; would need its own bean and spike.

**Verdict:** reordering a stop is a rare, deliberate act — not something done while driving — so half a second of hold is a fair price for leaving a verified fix and a settled row design alone. Revisit only if the row gets reworked for other reasons.
