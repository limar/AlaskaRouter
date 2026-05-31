---
# AlaskaRouter-y7kl
title: 'Tests: add unit-test target and smoke test'
status: completed
type: task
priority: high
created_at: 2026-05-27T08:06:47Z
updated_at: 2026-05-27T08:11:10Z
parent: AlaskaRouter-kupb
---

Add the baseline test harness so future tests can run.

- [x] Add `AlaskaRouterTests` to `project.yml`
- [x] Add a minimal smoke test under `Tests/`
- [x] Regenerate `AlaskaRouter.xcodeproj` with `xcodegen generate`
- [x] Verify `xcodebuild test` can run the new target

## Summary of Changes

Added the `AlaskaRouterTests` iOS unit-test target to `project.yml`, added `Tests/AlaskaRouterSmokeTests.swift` with two XCTest smoke tests against `QueryParser` and `SmartInsert`, regenerated `AlaskaRouter.xcodeproj`, and verified with `xcodebuild test -project AlaskaRouter.xcodeproj -scheme AlaskaRouter -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -skipMacroValidation -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO`. The command passed: 2 tests, 0 failures.
