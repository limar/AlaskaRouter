---
# AlaskaRouter-8xwu
title: 'Tests: SwiftData TripStore lifecycle'
status: completed
type: task
priority: normal
created_at: 2026-05-27T08:07:58Z
updated_at: 2026-05-27T08:30:02Z
parent: AlaskaRouter-kupb
---

Add in-memory SwiftData tests for trip lifecycle helpers.

- [x] Build an in-memory `ModelContainer` test helper
- [x] Test first-launch bootstrap creates and activates a trip
- [x] Test default-name suffix behavior
- [x] Test delete active trip falls back to another trip
- [x] Test deleting the final trip bootstraps a replacement
- [x] Test rename ignores blank names and saves valid names

## Summary of Changes

Added `Tests/TripStoreTests.swift` with in-memory SwiftData coverage for first-launch bootstrap, default-name suffixing, active-trip fallback after delete, automatic replacement after deleting the final trip, and rename validation. Reused the in-memory `ModelContainer` helper from `Tests/TestFactories.swift` and reset `TripStore.activeTripID` around each test to avoid UserDefaults leakage. Verified with `xcodebuild test`: 22 tests, 0 failures.
