---
# AlaskaRouter-xvb8
title: Tweaks sheet opens full-screen by default (drop .medium detent)
status: completed
type: task
priority: normal
created_at: 2026-05-26T16:29:25Z
updated_at: 2026-05-26T17:58:37Z
parent: AlaskaRouter-ka6b
---

The Tweaks panel sheet currently opens at .medium detent, requiring the user to drag it up to .large to see everything without scrolling. As the panel grows (new sections like the Cancel button design), this becomes friction.

## Fix

Drop .medium from the presentationDetents list. The sheet opens at .large (effectively full-screen) by default. Users who want a smaller view can pull down to dismiss.

## Todo

- [x] Change presentationDetents in RootView from [.medium, .large] to [.large]
- [x] Build & verify on simulator

## Summary of Changes

Dropped .medium from presentationDetents on the Tweaks sheet. Now opens full-screen by default; the user can still pull down to dismiss.
