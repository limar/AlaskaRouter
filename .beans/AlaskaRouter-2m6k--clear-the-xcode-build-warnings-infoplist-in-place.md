---
# AlaskaRouter-2m6k
title: Clear the Xcode build warnings (Info.plist in-place docs, TripPreviewRenderer concurrency, unused bindings)
status: completed
type: task
priority: normal
created_at: 2026-07-31T17:37:34Z
updated_at: 2026-07-31T18:07:33Z
---

The Xcode IDE shows a warning set on every build. Clear all of them at the source (project.yml / Info.plist / Swift), not by suppression.

Warnings observed (xcodebuild, Debug-iphonesimulator):

1. Target-level: "The application supports opening files, but doesn't declare whether it supports opening them in place. You can add an LSSupportsOpeningDocumentsInPlace entry..."
   - We register CFBundleDocumentTypes for `dev.alaskarouter.trip` (AlaskaRouter-h113) but never declare in-place support.

2. AlaskaRouter/Sharing/TripPreviewRenderer.swift — MapLibre pre-concurrency fallout:
   - add '@preconcurrency' to treat 'Sendable'-related errors from module 'MapLibre' as warnings
   - main actor-isolated static property 'inFlight' can not be mutated from a Sendable closure
   - capture of 'snapshotter' with non-Sendable type 'MLNMapSnapshotter' in a '@Sendable' / isolated closure
   - capture of 'completion' with non-Sendable type '(UIImage?) -> Void' in a '@Sendable' closure

3. AlaskaRouter/Map/MapLibreExtensions.swift — 8x "immutable value ... was never used" in CameraState.currentZoom.

## Todo
- [x] Decide + declare LSSupportsOpeningDocumentsInPlace
- [x] Fix TripPreviewRenderer concurrency warnings WITHOUT changing its timing (async shape rejected on evidence — see AlaskaRouter-pq9g)
- [x] Clean up CameraState.currentZoom pattern bindings
- [x] Full build is warning-clean (app + test targets); 133 tests pass
- [x] Verify the export preview still renders in the running app

## Summary of Changes

All Xcode warnings for the app + test targets are gone; `xcodebuild build` and `xcodebuild test` are clean.

**1. `LSSupportsOpeningDocumentsInPlace = YES`** (AlaskaRouter/Info.plist, next to the CFBundleDocumentTypes it describes). We read a `.akrtrip` at its original location inside a security-scoped bracket and materialize a *copy of the trip* in SwiftData, never writing back — so in-place is the accurate declaration, and it stops iOS dropping a duplicate into Documents/Inbox on every open (nothing cleans those up).

**2. `CameraState.currentZoom`** (AlaskaRouter/Map/MapLibreExtensions.swift): unused pattern bindings replaced with `_`; the two "unsupported" cases (`.rect`, `.showcase`) folded into one.

**3. `TripPreviewRenderer`** — four concurrency warnings, fixed at the source rather than suppressed:
- `@preconcurrency import MapLibre` — the module is pre-concurrency ObjC with no Sendable annotations anywhere.
- `inFlight` is now `[UUID: MLNMapSnapshotter]`, so the completion handler captures only a Sendable token instead of the snapshotter.
- The handler body runs in `MainActor.assumeIsolated` — `startWithCompletionHandler:` is documented to call back on the main queue, so this states a contract MapLibre already guarantees rather than hopping.
- `completion` is now `@escaping @MainActor (UIImage?) -> Void` (a global-actor-isolated closure is Sendable).

## Rejected: the async rewrite

The obvious cleanup — make it `async`, drop `inFlight` entirely — was implemented, then reverted after measuring it. An async shape forces both call sites into a `Task`, which starts the snapshot one main-thread turn later, and that loses a race with the live MapView over the PMTiles archive:

- snapshot started in the caller's turn: **10/12 launches OK**
- snapshot started one turn later: **1/12 launches OK**

That race is a pre-existing bug, now filed as **AlaskaRouter-pq9g (export preview snapshot flakily fails: "Error parsing PMTiles directory")** — it also means the bottom sheet's `.onChange(of: previewSignature)` re-render is probably failing nearly every time today. The async cleanup is parked behind that fix, and the reason is recorded as a NOTE ON SHAPE comment at the top of the file.
