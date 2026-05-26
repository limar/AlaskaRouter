---
# AlaskaRouter-qat6
title: On-map controls z-order — render below search sheet
status: completed
type: task
priority: high
created_at: 2026-05-26T16:29:13Z
updated_at: 2026-05-26T17:57:03Z
parent: AlaskaRouter-ka6b
---

When the search-results sheet is long enough to extend down to the bottom of the screen (visible after dismissing the keyboard via a drag-down), the on-map controls (LocateMe, zoom +, zoom −, scale indicator) float visually ABOVE the search sheet. They should stick to the map — i.e., be obscured by the search sheet when it overlaps them.

## Cause

In `RootView.swift`'s ZStack, the on-map controls VStack (and the scale) are rendered AFTER the bar/results VStack, so they sit above it in z-order.

## Fix

Move the on-map controls block to BEFORE the bar VStack in the ZStack. They stay anchored to the bottom of the screen, but now they're rendered earlier and the bar/results sheet covers them when overlap occurs.

## Todo

- [x] Move the on-map controls VStack earlier in the ZStack (before the bar VStack)
- [x] Verify allowsHitTesting(!isSearchActive) is still correct (controls should be non-interactive when search is active, regardless of visibility)
- [x] Build & verify on simulator

## Summary of Changes

Moved the on-map controls (LocateMe, +/-, scale) block from after the bar+results VStack to BEFORE it in RootView ZStack. Now the search sheet covers the controls when it overlaps them visually. allowsHitTesting(!isSearchActive) semantics preserved: taps pass through to the scrim below when search is active.
