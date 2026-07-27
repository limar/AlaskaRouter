---
# AlaskaRouter-ctco
title: Social export — "Look What I Did" wide trip map image
status: todo
type: feature
priority: normal
created_at: 2026-07-27T21:34:45Z
updated_at: 2026-07-27T21:34:45Z
---

Field-tested Alaska trip, July 2026. Wanted while travelling and missing: a way to show the trip off. A phone screenshot only captures the current viewport, so a 6093 km / 54-stop trip comes out cramped and unreadable.

## What it should produce
A single wide, shareable image of the **whole trip** — route ribbon, waystops, surrounding country — rendered at a resolution that survives being posted, not a screen-sized crop.

## Technical footing (and the one real risk)
`AlaskaRouter/Sharing/TripPreviewRenderer.swift` already renders offline basemap snapshots via `MLNMapSnapshotter` against the same bundled PMTiles style (shipped for AlaskaRouter-56kj). That gives us the basemap for free at any size and zoom.

**The risk:** the snapshotter renders the *style*, and our route lines + numbered waypoint markers are **not** in the style — they are injected onto the live map's style at runtime from `ExpeditionMapView.syncTripRouteLayer` / `syncMarkerLayers` inside `.unsafeMapViewControllerModifier`. So the snapshot comes back as bare terrain. Two ways out:
- **(i)** composite route + markers in Core Graphics over the snapshot (`compose()` at `TripPreviewRenderer.swift:63` already does this for a single marker — it would need the projection maths for a whole polyline), or
- **(ii)** refactor the layer builders to take an `MLNStyle` and reuse them against the snapshotter's style.
(ii) is the clean one and kills the duplication, but it is the bigger change. Settle this in a spike before committing to a look.

## Design surface — nothing gets built before this is agreed
- [ ] Aspect ratio(s): wide 16:9? square? 4:5 and 9:16 story? Offer a choice, or pick one?
- [ ] Framing: auto-fit the trip bbox with padding — and what happens with a trip that is one long thin diagonal (the Alaska case)?
- [ ] Overlay: trip name, total distance, stop count, block/day names, dates? How much is too much?
- [ ] Attribution / watermark: OSM + OpenTopoMap credit is **required** by licence; app branding is optional. Where does it sit?
- [ ] Entry point: bottom-sheet "…" menu? Trip header? A dedicated button?
- [ ] Does the user get to nudge the framing before sharing, or is it one-shot?

## Todo
- [ ] Spike: prove route + markers render into an `MLNMapSnapshotter` image at poster size — decide (i) vs (ii)
- [ ] Mock the output image variants (real renders of the Alaska trip, not sketches) and pick a look
- [ ] Agree the entry point + overlay content
- [ ] Implement, then share one for real
