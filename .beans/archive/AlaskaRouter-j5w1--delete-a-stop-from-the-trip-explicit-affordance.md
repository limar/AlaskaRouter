---
# AlaskaRouter-j5w1
title: Delete a stop from the trip (explicit affordance)
status: completed
type: feature
priority: high
created_at: 2026-05-19T12:13:50Z
updated_at: 2026-05-19T19:05:58Z
parent: AlaskaRouter-xtua
---

Today there's swipe-to-delete on stop rows in the bottom sheet via List.onDelete — works but only iOS power users discover it. The user wants delete as a high-priority core capability with a discoverable affordance.

Open design questions:
- Always-visible trash icon on each row vs swipe-only vs both?
- Confirmation alert (matches the trip-delete pattern) or silent?
- Undo toast (we already have AddedToTripToast as a model)?

- [x] Decide affordance with user
- [x] Implement
- [x] Verify with delete + re-add of the same stop (user to confirm on device — UI verified visually)

## Summary of Changes

- TripEditToast (generalized from AddedToTripToast) supports two kinds: .added (green mappin) and .removed (tomato trash). Old AddedToTripToast kept as a shim for compatibility.
- DeletedStopSnapshot value type (Data/DeletedStopSnapshot.swift) — frozen copy of id/order/coord/label/category captured BEFORE modelContext.delete, since the SwiftData reference can't be relied on afterward.
- TripBottomSheet:
  - waypointRow now wraps the row body in a Button (for tap-to-select) and renders a tomato trash button next to the existing drag handle.
  - All deletion paths (tap-trash + swipe-to-delete) go through a single deleteWaypoint(wp, renumberAfter:) chokepoint that builds the snapshot, calls modelContext.delete, then forwards the snapshot via onWaypointDeleted.
  - onWaypointDeleted callback signature changed from (Waypoint) to (DeletedStopSnapshot) so the parent gets safe data after the model object is gone.
- RootView:
  - recentlyDeletedSnapshot @State + a TripEditToast(.removed) appearance branch in the body (mutually exclusive with recentlyAddedWaypoint's toast).
  - handleSheetWaypointDeleted now triggers the toast + a 4s auto-dismiss task.
  - undoDelete inserts a new Waypoint at the original .order, shifts subsequent stops up, saves.
