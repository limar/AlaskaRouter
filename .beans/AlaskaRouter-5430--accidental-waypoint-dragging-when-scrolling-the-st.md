---
# AlaskaRouter-5430
title: Accidental waypoint dragging when scrolling the stop list
status: todo
type: bug
priority: high
created_at: 2026-07-27T23:28:04Z
updated_at: 2026-07-27T23:28:04Z
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
- [ ] Spike: can the grab be restricted to the handle without hand-rolling the whole reorder?
- [ ] Decide between custom drag and an explicit reorder mode
- [ ] Implement; verify by scrolling the 41-stop list aggressively without a single accidental move
