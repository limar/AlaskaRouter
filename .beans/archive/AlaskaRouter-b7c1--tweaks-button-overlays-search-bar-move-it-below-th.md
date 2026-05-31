---
# AlaskaRouter-b7c1
title: Tweaks button overlays search bar — move it below the bar
status: completed
type: task
priority: high
created_at: 2026-05-26T16:29:19Z
updated_at: 2026-05-26T17:59:04Z
parent: AlaskaRouter-ka6b
---

The tweaks trigger (wrench button, top-left) overlays the expanded search bar — both are anchored to the top of the screen with similar padding. When the bar is expanded, the tweaks button sits on top of the magnifying-glass icon area, looking like clutter.

## Fix

Move the tweaks button to a position that doesn't compete with the bar. Per user: "horizontally aligned with left or right control column but somewhat below the search bar."

The MapControls column is on the right edge (bottom). Put the tweaks button on the right edge but vertically just below the bar (top: ~64pt) — shares the right column visually with MapControls, but at the top.

## Todo

- [x] Update the tweaksTriggerButton positioning in RootView's VStack overlay
- [x] Visually verify no overlap with the bar in either focused or blurred state
- [x] Build & verify on simulator

## Summary of Changes

Moved the tweaks wrench button from top-left/top-8pt to top-right/top-72pt. Right-aligned with the MapControls column (also right-edge) and vertically below the expanded search bar so they never overlap.
