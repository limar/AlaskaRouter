---
# AlaskaRouter-zaha
title: Add system red to Cancel button color palette
status: completed
type: task
priority: normal
created_at: 2026-05-26T16:29:31Z
updated_at: 2026-05-26T17:58:42Z
parent: AlaskaRouter-ka6b
---

The Cancel button design spike (y7l0) ships with 6 color options: slate blue, brand blue, system blue, charcoal, secondary gray, teal — all cool tones. The user wants to also try system red — the iOS convention for Cancel/delete/destructive actions.

## Fix

Add a 7th entry to the Cancel palette:
- TweaksStore: extend cancelButtonColor docs to mention index 6 = system red
- FloatingSearchBar.cancelPaletteColor: case 6: return .red (system red is dynamic light/dark-aware)
- TweaksPanel: add "6 — System red" to the color Picker

## Todo

- [x] Add system red as palette index 6 in FloatingSearchBar
- [x] Update TweaksStore docs
- [x] Add picker option in TweaksPanel
- [x] Build & verify on simulator; on-device A/B against current default

## Summary of Changes

Added system red (Color.red — adaptive light/dark) as palette index 6 in FloatingSearchBar.cancelPaletteColor. Updated TweaksStore docs to reflect the 7-color palette. Added the picker entry to the Cancel Color menu in TweaksPanel.
