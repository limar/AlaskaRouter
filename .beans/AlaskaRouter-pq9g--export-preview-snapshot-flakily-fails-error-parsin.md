---
# AlaskaRouter-pq9g
title: 'Export preview snapshot flakily fails: ''Error parsing PMTiles directory'''
status: todo
type: bug
priority: normal
created_at: 2026-07-31T18:05:27Z
updated_at: 2026-07-31T18:05:27Z
---

`MLNMapSnapshotter` intermittently fails to read the bundled PMTiles archive while the live `MapView` is reading the same file. The completion handler returns:

```
Error Domain=MLNErrorDomain Code=6 "Error parsing PMTiles directory: map::at:  key not found"
```

When it fires, `TripPreviewRenderer` yields nil and the share sheet silently falls back to the app icon instead of the map thumbnail (AlaskaRouter-56kj). No crash, no user-visible error — just a worse preview.

## Evidence (measured 2026-07-31, iPhone 17 Pro sim, iOS 26.5)

Launch-time render (snapshot started synchronously in the same main-thread turn as `.onAppear`, i.e. before the MapView starts pulling tiles):

- **10 / 12 launches OK**

Deferred render (identical renderer, but the call wrapped in `Task { }` so the snapshot starts one main-thread turn later, after the MapView is loading):

- **1 / 12 launches OK**

Both call sites (spike dump + bottom-sheet preview) fail together when it happens, so it's per-launch, not per-snapshotter. Reproduce with:

```bash
xcrun simctl launch --console-pty booted dev.alaskarouter.AlaskaRouter -seedDemoTrip YES -spikePreview "63.07,-151.0"
```

## Why it matters beyond the launch render

`TripBottomSheet` also regenerates the preview from `.onChange(of: previewSignature)` — renaming a trip or changing its first stop re-renders while the map is fully live, which is exactly the ~1/12 regime. That path is probably failing almost every time today.

## Consequences already felt

This is why `TripPreviewRenderer` is still a completion-handler API rather than `async`: an async shape forces the call sites into a `Task`, which is the 1/12 timing. See the NOTE ON SHAPE comment at the top of AlaskaRouter/Sharing/TripPreviewRenderer.swift. Fixing this unblocks that cleanup.

## Todo
- [ ] Find the actual contention — MapLibre's PMTiles directory cache (`map::at`) shared between the MapView's file source and the snapshotter's
- [ ] Check whether a newer maplibre-gl-native has a fix (we pin swiftui-dsl @ main)
- [ ] Decide the app-side shape: separate archive/file-source for the snapshotter, or serialize snapshot against map load
- [ ] Re-measure: 12/12 launches OK, plus a mid-session regenerate (rename trip → preview updates)
- [ ] Then revisit making TripPreviewRenderer async
