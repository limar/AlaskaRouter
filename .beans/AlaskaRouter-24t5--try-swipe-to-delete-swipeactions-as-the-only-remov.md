---
# AlaskaRouter-24t5
title: 'Try: swipe-to-delete (.swipeActions) as the only remove path on stop rows; drop the trash button'
status: completed
type: task
priority: high
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T09:54:10Z
parent: AlaskaRouter-e0vm
---

Replace the always-visible red trash-circle on every stop row with Apple-standard .swipeActions. Two-step gesture (swipe → tap red Delete) IS the confirmation, so no toast. Keeps DeletedStopSnapshot in the model for a future undo path.

Reject path: if after a session the button-less rows feel under-discoverable, add a small minus.circle that triggers an immediate delete (gesture stays the confirm-by-swipe path). Custom-roll the 'tap minus animates the swipe-reveal' UX only if both prior steps fall short.

Accept criterion: every stop row's trailing edge gets visibly lighter; swipe-to-delete works; no toast.

## Summary
Dropped the in-row trash button from waypointRow. Swipe-to-delete via List's .onDelete (already wired) is now the single delete path — Apple-standard, two-step gesture is the confirmation. Trailing edge of every stop row visibly lighter; the row chrome stops shouting DELETE on every line.
