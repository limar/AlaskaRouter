---
# AlaskaRouter-ijy9
title: Lock / archive a trip (read-only, memory-safe)
status: draft
type: feature
priority: normal
created_at: 2026-07-27T22:41:21Z
updated_at: 2026-07-27T22:41:21Z
---

From the Alaska field trip, July 2026. Finished trips are memories. Right now nothing stops an accidental drag, swipe-delete or smart-insert from quietly rewriting one.

## What is wanted
A way to mark a trip read-only — "locked", "archived", or similar — so it can be opened and admired but not edited by accident.

## To decide
- **Lock vs archive — are these one feature or two?** Lock = still in the active list, just not editable. Archive = moved out of the main list into a separate section, implying lock. The trip switcher already exists (AlaskaRouter-7k2b), so archive has somewhere to go.
- What exactly is frozen? Waypoints and blocks clearly. What about the *routing* — should a locked trip still refresh pendingSnap legs when the network returns (AlaskaRouter-2l0i / the pendingSnap auto-refresh design)? Recomputing geometry is arguably not "editing", and a locked trip with permanently dashed legs would be a sad memento.
- How is it unlocked, and how obvious should that be? Too easy and it doesn't protect; too hidden and it's annoying.
- Does a locked trip show any on-map or in-sheet indicator?

## Notes
Touches every mutation path in `TripBottomSheet` (reorder, swipe-remove, add separator) plus `SmartInsert` and the callout add/remove actions — the guard wants to live in one place (TripStore or the model) rather than being sprinkled across the UI.
