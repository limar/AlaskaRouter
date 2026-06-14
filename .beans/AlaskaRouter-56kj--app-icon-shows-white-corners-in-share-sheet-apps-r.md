---
# AlaskaRouter-56kj
title: 'Export share-sheet preview: per-trip map snapshot of first waypoint'
status: completed
type: feature
priority: normal
created_at: 2026-06-14T16:24:38Z
updated_at: 2026-06-14T19:06:21Z
---

The top of the iOS share sheet is a PREVIEW of the document being shared (separate UI role from the apps-row app icon, and from the static Files-app type icon). We supply that preview as an image via `SharePreview(image:)`. Instead of the app icon, render a real map snapshot of the trip so the export is recognizable and beautiful.

## Decision (2026-06-14)
- Per-trip preview: square map at zoom 8-9 centered on the trip's FIRST waypoint, with its marker + name. Empty trips fall back to a generic map sample with a no-name pin.
- This is sender-side only (the share-sheet preview). It does NOT change the Files-app file icon (a static type icon) — that stays as-is / future proper document icon.
- Approach approved: spike the offline snapshot path first, then build.

## Why feasible
- We already `import MapLibre` (native), which exposes `MLNMapSnapshotter` / `MLNMapSnapshotOptions` / `MLNMapCamera`.
- `ExpeditionMapView.styleURL` (built from the bundled PMTiles) is reusable -> the snapshotter renders the same offline basemap, no network.

## Open risk to retire in the SPIKE
- Unknown: does `MLNMapSnapshotter` (a separate render path from the live `MLNMapView`) resolve our custom `pmtiles://` scheme? The scheme is registered inside the MapLibre package, not our code; need to confirm it works in the snapshotter.
- If snapshotter can't do pmtiles -> fallback: capture an offscreen `MLNMapView` (same renderer that already works), or a constant bundled sample image.

## Plan
### Spike (do first)
- [x] Exposed styleURL (made module-internal); added TripPreviewRenderer.render using MLNMapSnapshotter.
- [x] SPIKE GREEN: LaunchArg -spikePreview writes Documents/preview-spike.png. Confirmed the OFFLINE basemap renders in MLNMapSnapshotter (Denali 63.73,-148.91 z8.5 — hillshade, labels, Parks Hwy). pmtiles:// resolves in the snapshotter. Note: MapLibre bakes an attribution strip at the bottom — decide keep/crop.
### Build (after spike green)
- [x] Compose marker (white ring / trip-color disc / white center) + name pill over the snapshot (UIGraphicsImageRenderer). Verified composited output from the real app.
- [x] Pre-render into @State on appear + on previewSignature change; SharePreview uses tripPreviewImage ?? app-icon fallback. First-waypoint center, z8.5, 600px square.
- [x] Empty-trip fallback: generic Denali-massif center, no name pill.
- [x] Verified: composited image pulled from the running app, AND user eyeballed the in-sheet SharePreview ("looks good"). Attribution kept. Dev-only -spikePreview LaunchArg kept as a headless verification affordance.

## History
Repurposed from the app-icon white-corner bug. That patch (flood-fill, commit reverted) was abandoned: the real win is this preview. The app-icon white corners remain a separate, deferred cosmetic issue (needs proper full-bleed art); not tracked here anymore.

## Summary
Export share-sheet preview now renders a per-trip OFFLINE map snapshot of the first waypoint (MLNMapSnapshotter + bundled PMTiles) with a marker + name pill, fed to SharePreview (app-icon fallback until ready; generic-center fallback for empty trips). Spike retired the pmtiles-in-snapshotter risk. User-confirmed complete.
