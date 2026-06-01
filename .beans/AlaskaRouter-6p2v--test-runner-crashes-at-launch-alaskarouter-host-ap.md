---
# AlaskaRouter-6p2v
title: 'Test runner crashes at launch: AlaskaRouter host app hits fatalError on missing pmtiles'
status: completed
type: bug
priority: critical
created_at: 2026-06-01T08:37:40Z
updated_at: 2026-06-01T08:39:05Z
---

## Symptom

Running the AlaskaRouterTests scheme (`xcodebuild ... test`) crashes the test host app before any XCTest can run:

```
AlaskaRouter/ExpeditionMapView.swift:23: Fatal error: Missing alaska-pack.pmtiles in bundle
AlaskaRouter (pid) encountered an error (Early unexpected exit, operation never finished bootstrapping)
```

This reproduces on master without any local changes — i.e. nobody can run the test suite locally without first manually fetching the gitignored `alaska-pack.pmtiles` asset.

## Root cause

`AlaskaRouterTests` uses `TEST_HOST` = the AlaskaRouter app (per [project.yml](project.yml)). XCTest launches that binary, which runs `@main AlaskaRouterApp` → `WindowGroup { RootView() }` → RootView instantiates `ExpeditionMapView`, whose `MapView(styleURL: styleURL, ...)` access resolves the file-scope `styleURL` global at [AlaskaRouter/Map/ExpeditionMapView.swift:18](AlaskaRouter/Map/ExpeditionMapView.swift:18). That global is a `let` initializer that `fatalError`s on missing `alaska-pack.pmtiles`. The pmtiles asset is gitignored (`*.pmtiles` in .gitignore — too large for GitHub's 100 MB cap, distributed via Releases) so a clean checkout cannot run tests without first fetching the asset.

## Fix (proposed)

Detect XCTest at the very top of the SwiftUI Scene and host an `EmptyView` for the test runner. Production launches still need the asset and must still abort hard if it's missing (so a real packaging error doesn't ship to the App Store) — the fatalErrors stay. We only short-circuit BEFORE we'd touch any asset-dependent view.

Detection: `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`. Standard XCTest signal, set by the test runner.

This is NOT defensive programming — we are NOT swallowing the asset error in production. We are stating clearly: under XCTest, the app host's only job is to launch so the test bundle can attach; rendering RootView is out of contract.

## TODOs

- [x] Add `isRunningUnderXCTest` helper in `AlaskaRouter/App/AlaskaRouterApp.swift`.
- [x] Branch WindowGroup body to render `EmptyView()` under XCTest, RootView otherwise.
- [x] Re-run `xcodebuild ... test` — 37/37 tests pass, no bootstrapping crash.
- [x] Comment added at the branch citing this bean and the invariant: production launch must still hit RootView and crash hard on a missing asset.

## Summary of Changes

In [AlaskaRouter/App/AlaskaRouterApp.swift](AlaskaRouter/App/AlaskaRouterApp.swift) split the WindowGroup body into a test-host branch (`EmptyView()`) and the production branch (`RootView() + container + onAppear`). Test detection via `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil` — the standard XCTest environment signal.

Production launch path is unchanged. The fatalErrors in `ExpeditionMapView.styleURL` are intentionally preserved so a real packaging error (missing pmtiles, glyphs, places.geojson) on a release build aborts loudly and never ships.

Result: 37/37 tests pass under `xcodebuild ... -scheme AlaskaRouter ... test`.
