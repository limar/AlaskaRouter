---
# AlaskaRouter-rr71
title: Remove the 'Removed from trip — Undo' toast
status: completed
type: task
priority: high
created_at: 2026-05-24T15:58:44Z
updated_at: 2026-05-29T14:44:26Z
parent: AlaskaRouter-ka6b
---

User feedback (2026-05-24): toasts clutter the UI. Following on from wqt4 (which already removed the `.added` toast), drop the `.removed` toast too.

## Inventory of toasts

There are only two toasts in the app — both \`TripEditToast\` from \`AddedToTripToast.swift\`:
- \`.added\` — already dormant (wqt4 stopped populating \`recentlyAddedWaypoint\`).
- \`.removed\` — still active. This bean kills it.

Not removing: \`WelcomeOverlay\` (first-launch overlay — different concept, user didn't flag it).

## Scope

- Stop populating \`recentlyDeletedSnapshot\` in \`handleSheetWaypointDeleted\`.
- The trash button in the sheet becomes immediate-delete with no undo. (User can re-add via search if it was a mistake.)
- Leave the dormant view-rendering block + the \`undoDelete\` function as dead code for easy reversal later.

## Checklist

- [ ] Drop \`recentlyDeletedSnapshot = snapshot\` assignment
- [ ] Drop the \`scheduleDeletedToastDismiss\` call
- [ ] Build + verify no behavior regression


## Summary of Changes

`handleSheetWaypointDeleted` no longer assigns `recentlyDeletedSnapshot = snapshot` and no longer calls `scheduleDeletedToastDismiss`. The "Removed from trip — Undo" toast view block remains in `RootView` (line 267, gated on `recentlyDeletedSnapshot`) as dormant code — never triggered now. Same dormant pattern as wqt4's `.added` toast cleanup.

After this change, the app has zero active toasts. (`WelcomeOverlay` is a separate concept — full-screen first-launch card, not a toast.)
