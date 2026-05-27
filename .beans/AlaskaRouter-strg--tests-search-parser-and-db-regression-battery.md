---
# AlaskaRouter-strg
title: 'Tests: search parser and DB regression battery'
status: completed
type: task
priority: high
created_at: 2026-05-27T08:07:45Z
updated_at: 2026-05-27T08:25:59Z
parent: AlaskaRouter-kupb
---

Add search-focused tests for parser behavior and DB-backed retrieval regressions.

- [x] Test `QueryParser` category phrase extraction and token behavior
- [x] Test `EditDistance` prefix and typo behavior
- [x] Make `PlacesDB` test-loadable without relying on `Bundle.main` if needed (not needed: hosted unit tests load the app bundle resource)
- [x] Add small DB-backed search battery against `alaska-places.sqlite`
- [x] Add explicit SQL category bind-order regression test from `SPIKE_FINDINGS.md`

## Summary of Changes

Added `Tests/SearchTests.swift` covering category phrase parsing, duplicate category-hint dedupe, edit-distance prefix/typo behavior, a DB-backed search battery through `SearchService` against the bundled `alaska-places.sqlite`, and the `Fairbanks ranger` category-hint bind-order regression from `SPIKE_FINDINGS.md`. Hosted tests can load `alaska-places.sqlite` from the app bundle, so no `PlacesDB` production change was needed. Verified with `xcodebuild test`: 17 tests, 0 failures.
