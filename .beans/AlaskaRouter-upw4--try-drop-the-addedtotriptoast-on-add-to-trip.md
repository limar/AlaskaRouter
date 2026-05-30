---
# AlaskaRouter-upw4
title: 'Try: drop the AddedToTripToast on add-to-trip'
status: completed
type: task
priority: normal
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T09:54:10Z
parent: AlaskaRouter-e0vm
---

User wants no toasts anywhere. The newly-added row appearing in the list is feedback enough; the toast is noise on top. Remove the AddedToTripToast surface; keep the underlying handler in case we ever want a different feedback channel (e.g. brief haptic). Verify the add flow still feels confirmed.

## Summary
Dropped both TripEditToast surfaces (added + removed). The underlying state (recentlyAddedWaypoint, recentlyDeletedSnapshot) stays so a future feedback channel (haptic, shake-to-undo, ⌘Z) can be wired without rewiring the mutation paths.
