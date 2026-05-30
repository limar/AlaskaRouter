---
# AlaskaRouter-5w58
title: 'Bug: switching active trip in the trips list stops working'
status: completed
type: bug
priority: high
created_at: 2026-05-30T08:11:20Z
updated_at: 2026-05-30T08:14:35Z
---

Tapping a different trip in the bottom-sheet trips list closes the list but the app stays on the current trip; New Trip still works. Regression spotted by user.

Root cause: RootView declares @AppStorage("activeTripID") private var activeTripIDObserved with a comment claiming it triggers re-renders on TripStore.setActive — but the property is NEVER read inside body, so SwiftUI never tracks the dependency. setActive writes UserDefaults directly (bypasses @AppStorage); without a body read of activeTripIDObserved, only the mode @Binding writes from switchTo were keeping the chain alive. createNewTrip works because it also mutates SwiftData → @Query trips array refreshes → re-render.

Fix: make activeTrip's computed explicitly read activeTripIDObserved so SwiftUI tracks the dependency. setActive then reliably triggers a re-render → activeTrip recomputes → new trip rendered.

## Tasks
- [x] Diagnose
- [x] Apply one-line fix in activeTrip computed
- [x] Build + install + verify trip switching works — user confirmed: "works. Fixed."

## Summary of Changes
One-line fix: activeTrip's computed now reads activeTripIDObserved (`_ = activeTripIDObserved`) so SwiftUI tracks the @AppStorage dependency. TripStore.setActive writes UserDefaults["activeTripID"] directly; with the in-body read in place, that write triggers a re-render → activeTrip recomputes → new trip rendered.
