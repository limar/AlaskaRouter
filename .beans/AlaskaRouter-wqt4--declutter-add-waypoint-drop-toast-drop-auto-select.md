---
# AlaskaRouter-wqt4
title: Declutter Add Waypoint — drop toast, drop auto-select
status: in-progress
type: feature
priority: high
created_at: 2026-05-24T09:55:55Z
updated_at: 2026-05-24T10:09:15Z
parent: AlaskaRouter-ka6b
---

Tapping \"Add to trip\" on a search result currently does THREE things:
1. Shows the AddedToTripToast (\"Added · Undo\") for ~4s
2. Auto-selects the newly added waypoint
3. Auto-opens the StopCallout on the new waypoint

User feedback (2026-05-24):
> remove the toast with \"Undo\" upon add, don't select the added point (or at very least don't show the callout). In the near future we may decide to return the selection but that's when we rework the selection style to something easy on eye (same icon but floating in the air or some thin additional circle around it).

## Scope

- Drop the toast entirely on add (the action is itself the confirmation — a marker appears on the map).
- After add, don't set \`selectedWaypointID\` (or set it but don't open the callout).
- Map should pan/zoom toward the new waypoint only if it's offscreen — gentle, no callout pop.

## Out of scope

- Removed-toast (Undo for delete) — keep this, deletion is destructive and needs a safety net.
- Reworking the selection visual (the \"floating icon + thin ring\" idea) — separate bean later.

## Checklist

- [ ] Identify the add-waypoint code path (RootView.handleFastAdd, handleAddPreviewed)
- [ ] Drop the toast emit on \`.added\`
- [ ] Drop the auto-select (or just drop the callout open)
- [ ] Verify removal flow still emits the toast (Undo path must keep working)
- [ ] On-device check


## Fix applied (2026-05-24)

`handleAddPreviewed` and `handleFastAdd` in RootView no longer:
- set `selectedWaypointID = new.id` (which previously opened the StopCallout on the new waypoint)
- set `recentlyAddedWaypoint = new` (which displayed the "Added · Undo" toast for ~4s)
- call `scheduleToastDismiss(...)` (paired with the toast)

The marker appearing on the map + the new row in the bottom sheet are now the only confirmations. The map camera still gently pans to the new waypoint so the user sees what they just added.

Dormant code preserved (not deleted): the toast rendering block (`if let added = recentlyAddedWaypoint { ... }`), `scheduleToastDismiss`, and `undoAdd` all remain in the file as a no-op chain. Easy to re-enable if we change our minds. The `@State var recentlyAddedWaypoint` stays declared since it's referenced in a couple of cleanup spots that fire on deletion — harmless reads of a never-set value.

- [x] Identify the add-waypoint code path
- [x] Drop the toast emit (recentlyAddedWaypoint assignment)
- [x] Drop the auto-select (selectedWaypointID assignment)
- [x] Verify removal flow still emits its own toast (Undo path for delete is separate and intact)
- [ ] On-device check
