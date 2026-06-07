---
# AlaskaRouter-2ptw
title: 'Tile pack: scrape z=11..13 for Alaska for closer-look detail'
status: completed
type: feature
priority: high
created_at: 2026-05-25T14:34:45Z
updated_at: 2026-06-07T08:45:47Z
parent: AlaskaRouter-xtua
blocked_by:
    - AlaskaRouter-6ihk
---

User feedback after vyfe shipped (2026-05-25):
> I zoomed-in to the maximum and still had dots without names. Does it mean we limited the zooming too early or planned to download more tiles for closer look and never did it?

## Context

Current tile pack `alaska-pack.pmtiles` ships z=0..5 (world skeleton) + z=6..10 (Alaska). The "+" button on map controls clamps to `effectiveMaxZoom` = 10 read from the manifest (AlaskaRouter-i3jz fix). At z=10, OpenTopoMap tiles are coarse for fine-grained label placement.

The original design choice was to cap at z=10 to keep the bundled pack under ~500 MB. Going to z=11/12/13 multiplies tile count by 4×/16×/64×.

## Cost estimate

| Max zoom | Approx tile count (Alaska only, lat 51-72 lon -180 to -130) | Pack size |
|---|---|---|
| z=10 (current) | ~5,000 | ~470 MB |
| z=11 | ~20,000 | ~1.5 GB |
| z=12 | ~80,000 | ~5 GB |
| z=13 | ~320,000 | ~18 GB |

z=11 might still ship as a single GitHub Release asset (limit 2 GB per file). z=12+ would need either per-region splits or streaming.

## Alternatives

1. **z=11 only** — biggest visible improvement per byte. Probably 1.5 GB pack. Still bundleable.
2. **Selective z=12 over the touring corridors** (Anchorage→Fairbanks→Coldfoot+Dalton Highway corridor, Denali, Kenai, SE) and z=10 elsewhere. Custom tile-set assembly.
3. **Vector tiles for high zoom** — if we self-render OTM regionally (AlaskaRouter-6ihk), we can emit vector tiles for z=11+ and stay tiny.

## Open

Worth doing for v1? Or accept current 10-zoom limit and revisit when v2+ multi-region pack format is designed.

## Checklist

- [x] Decide z=10 vs z=11 vs corridor-selective
- [ ] If shipping z=11: re-run tools/build-pack/download_tiles.py for the new range
- [ ] Rebuild the pmtiles, push as a new data/ release tag

## Decision (2026-05-28)

Priority is visible map detail now; package infrastructure is secondary. Build a new single Alaska pack with statewide z=11 added on top of the existing world z=0..5 + Alaska z=6..10 coverage. Do not build the runtime downloadable-pack system first. Do not attempt statewide z=12/z=13 for v1 because the size multiplier is too large; revisit corridor-selective z=12/z=13 only if z=11 still feels insufficient on device. Continue hosting the resulting v1 artifact via GitHub Releases and installing it through the existing fetch-pack flow.

## Build Notes (2026-05-28)

Local disk check: 185 GiB free on the workspace volume, enough for z=11 scratch. Exact dry-run target for the final z=0..11 pack is 101,631 tiles: 1,365 world skeleton tiles, 25,311 existing Alaska z=6..10 tiles, and 74,955 new Alaska z=11 tiles.

To reduce bandwidth, build only the z=11 delta first, then merge it with the existing z=0..10 `alaska-pack.pmtiles`. Expected network transfer is roughly the z=11 PNG payload only (order of 1-2 GiB, depending OpenTopoMap tile sizes), plus GitHub upload/download of the final release asset later. Expected scratch footprint is the z=11 MBTiles, z=11 PMTiles, and merged PMTiles; well below available disk.

Started the z=11-only download into `tools/build-pack/data/alaska-z11-only.mbtiles` with 2 workers and 0.45s per-worker delay. Initial measured rate was ~1.5 tiles/sec, so this may take overnight; the MBTiles writer is resumable.

Paused the public-tile-server download after 2,345 rows were written (~15 MiB scratch) because this is a bulk offline archive request. The partial MBTiles remains in `tools/build-pack/data/` and can resume, but the next step should be explicit: either confirm permission/acceptable-use for the OpenTopoMap tile source, or switch to self-rendering / another source intended for offline bulk packages.

## Summary of Changes
Statewide Alaska z=11 detail shipped. Built by self-rendering (AlaskaRouter-6ihk) rather than scraping public tiles. Final corrected pack (with EPSG:3857 hillshade + geographic contours) installed 2026-06-07: 101,631 tiles total, maxzoom 11, 1.04 GB, bundled in the app. Higher zooms (z12-13) deferred to corridor region packs — see AlaskaRouter-r1cf.
