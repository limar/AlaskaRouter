---
# AlaskaRouter-kupb
title: Start adding tests
status: completed
type: feature
priority: normal
created_at: 2026-05-21T15:18:16Z
updated_at: 2026-05-27T08:35:33Z
parent: AlaskaRouter-xtua
---

## Test Strategy Assessment

- [x] Inspect current app architecture and existing test target
- [x] Identify high-value testable seams
- [x] Identify low-value or hard-to-test areas
- [x] Recommend whether to start now and first test slice

## Implementation Checklist

- [x] Add an `AlaskaRouterTests` unit-test target to `project.yml` and regenerate the project
- [x] Add a small test-data factory for in-memory `Trip`, `Waypoint`, and `BlockSeparator` graphs
- [x] Add pure unit tests for `SmartInsert`, `Trip.blocks`, `Trip.routeRibbons`, snap-cache encode/decode, `QueryParser`, and `EditDistance`
- [x] Add a focused search integration test using `alaska-places.sqlite`, including the known category-bind-order regression
- [x] Add SwiftData in-memory tests for `TripStore` lifecycle behavior
- [x] Defer MapLibre rendering/UI snapshot tests until the product UI settles further

## Findings

Current state:

- `Tests/` exists but is empty.
- `project.yml` defines only the `AlaskaRouter` app target; `xcodebuild -list` confirms there is no test target.
- The codebase now has enough non-UI logic that tests would catch real regressions, especially in route ordering, block derivation, search parsing/SQL, and cached route geometry.

Recommendation: start adding tests now, but keep the first pass narrow. Do not try to snapshot the whole app or automate MapLibre UI behavior yet. The product is still moving quickly, so broad UI tests would be expensive and brittle. The right move is a small unit/integration harness around stable product invariants.

## What We Should Test Now

1. **Trip/data invariants**

- `SmartInsert.position` and `insertSmart`: empty/one-stop append, cheapest-edge insertion between stops, order renumbering.
- `Trip.blocks` and `Trip.listItems`: implicit block 0, separator after missing/last waypoint is ignored, colors rotate predictably, all waypoints belong to exactly one block.
- `Trip.blockGeometries` and `Trip.routeRibbons`: straight-line fallback, block-color split at boundaries, out-and-back pass detection, dashed fallback flag when no snapped geometry exists.
- `Trip.cachedSnappedCoords`: valid key hydrates, stale key returns nil, malformed JSON returns nil, set/clear behavior.

2. **Search logic**

- `QueryParser.parse`: multi-word category phrases, duplicate category hints, category-vs-name token split.
- `EditDistance`: typo behavior and prefix distance behavior.
- A small DB-backed search battery using the bundled `alaska-places.sqlite`: Denali, Anchorage, Atigun typo, Wrangell visitor center, Fairbanks ranger, Chena hot spring.
- Specific regression from `SPIKE_FINDINGS.md`: category-hint SQL bind order. A query with category hints plus name tokens should still return name matches, not plausible-but-wrong category-only rows.

3. **App state helpers**

- `TripStore.defaultName`, `createEmpty`, `delete`, `rename`, and active-trip fallback using an in-memory SwiftData `ModelContainer`.
- This is worthwhile because the app must never become trip-less and active-trip recovery is user-visible.

4. **Small pure helpers once exposed or moved**

- `TripSheetDetent.height/next` is already trivial and testable, but low value.
- `TilePackManifest.effectiveMaxZoom` is testable if we add an initializer/fixture path later. Not a first-pass priority.

## What We Should Not Test Yet

- **MapLibre rendering correctness**: most important map defects are visual/cartographic: label legibility, icon overlap, route ribbon feel, raster tile look, tap hit testing through native layers. Unit tests cannot prove those well, and full UI tests would be fragile against MapLibre internals and style/resource timing. Keep using manual simulator/device verification and targeted visual spikes for now.
- **SwiftUI layout polish**: search bar shape, bottom-sheet material, callout placement, control z-order, and interaction feel are still changing. Snapshot tests would create churn and likely slow iteration.
- **Live OSRM routing behavior**: public network endpoint, latency, rate-limits, and remote response changes make this a poor unit-test dependency. Test URL/response parsing only after `OSRMProvider` gets injectable `URLSession` or a small transport protocol.
- **CoreLocation permission flows**: these need simulator/device automation and privacy reset steps. Keep them as manual smoke tests until distribution/CI work.
- **Generated visual assets/icons**: useful later via image snapshots, but today the designs are still being tuned with the Tweaks panel.

## Test Harness Shape

- Add `AlaskaRouterTests` as an iOS unit-test target in `project.yml`; keep `project.yml` the source of truth and regenerate the Xcode project with `xcodegen generate`.
- Use Swift Testing if Xcode 26.5 handles the app target cleanly; XCTest is acceptable if host-app/resource setup is simpler. The important part is getting tests running under `xcodebuild test`.
- Prefer internal testable seams over large refactors. Avoid making UI-private helpers public just for tests.
- For search integration, either include `alaska-places.sqlite` in the test bundle or add a test-only/file-path initializer to `PlacesDB`; the current `PlacesDB(bundleResource:)` is tied to `Bundle.main`, which is awkward for isolated tests.
- For pure logic on `Trip`/`Waypoint`, create in-memory SwiftData objects directly. If SwiftData relationships are annoying in plain unit tests, use a tiny helper factory rather than app bootstrapping.

## First Slice

1. Add the test target and make one empty test pass in `xcodebuild test`.
2. Add `SmartInsert` tests and `QueryParser`/`EditDistance` tests. These need the least infrastructure and will prove the harness.
3. Add `Trip.blocks` / `routeRibbons` tests with small synthetic trips.
4. Add the DB-backed search regression test after deciding how the test target should load `alaska-places.sqlite`.

## Summary of Changes

Added the first stable test suite for the app: a hosted `AlaskaRouterTests` target in `project.yml`, smoke coverage, reusable test factories, pure data/route invariant tests, DB-backed search/parser regression tests, and in-memory SwiftData `TripStore` lifecycle tests. Regenerated the Xcode project and verified the suite with `xcodebuild test`.

MapLibre rendering and SwiftUI/UI snapshot automation remain intentionally deferred until the product UI and map behavior settle; `AlaskaRouter-q1qn` tracks that future work as a draft/deferred child.

## Child Beans

Created ordered child beans:

- AlaskaRouter-y7kl — Tests: add unit-test target and smoke test — completed
- AlaskaRouter-sl7o — Tests: pure data and route invariants — completed
- AlaskaRouter-strg — Tests: search parser and DB regression battery — completed
- AlaskaRouter-8xwu — Tests: SwiftData TripStore lifecycle — completed
- AlaskaRouter-q1qn — Tests: defer map UI automation until stable — draft/deferred
