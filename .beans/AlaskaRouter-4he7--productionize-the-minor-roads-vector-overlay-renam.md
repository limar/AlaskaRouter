---
# AlaskaRouter-4he7
title: Productionize the minor-roads vector overlay (rename, manifest, refresh flow)
status: todo
type: task
priority: normal
created_at: 2026-06-10T13:31:28Z
updated_at: 2026-06-10T16:06:48Z
parent: AlaskaRouter-7avb
---

## Why
The [[levi]] spike was approved and already scaled statewide (28 MB, 122k features, bundled). What ships today still wears spike clothes. Make it a first-class subsystem of the map pack.

## Tasks
- [ ] Rename artifacts off "-spike": minor-roads-spike.pmtiles -> alaska-minor-roads.pmtiles (or fold INTO the main pack pipeline naming), tools/vector-roads-spike/ -> tools/vector-roads/; update style-base.json, ExpeditionMapView, build script install path, project regen.
- [ ] Manifest: record the overlay in alaska-pack.manifest.json (or a sibling entry) -- version/byte_size/source vintage (PBF date), so pack tooling knows about it.
- [ ] Data vintage & refresh: the overlay is built from the laptop's build-places PBF; wire its rebuild into the pack release flow (same Geofabrik fetch), so roads and raster don't drift apart across releases.
- [x] Real-device perf confirmed by user (2026-06-10): "Works nicely, looks as expected."
- [ ] Styling taste pass on device: widths/dashes per class, display minzoom (currently track/roads 9, paths 10).
- [ ] Attribution: tiles are OSM-derived -- already covered by the existing OSM credit, but confirm wording covers the vector overlay too ([[1tpz]] touches the same screen).

## Invariant to preserve (from [[qp29]])
Exactly one layer owns each highway class: raster=major, vector=minor. If Track A ([[f7tt]]) ever re-renders the raster roads-free, the vector side widens to all classes IN THE SAME CHANGE -- never both drawing the same class.
