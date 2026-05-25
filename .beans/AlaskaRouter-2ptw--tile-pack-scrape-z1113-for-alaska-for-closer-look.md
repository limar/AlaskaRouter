---
# AlaskaRouter-2ptw
title: 'Tile pack: scrape z=11..13 for Alaska for closer-look detail'
status: todo
type: feature
priority: low
created_at: 2026-05-25T14:34:45Z
updated_at: 2026-05-25T14:34:45Z
parent: AlaskaRouter-xtua
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

- [ ] Decide z=10 vs z=11 vs corridor-selective
- [ ] If shipping z=11: re-run tools/build-pack/download_tiles.py for the new range
- [ ] Rebuild the pmtiles, push as a new data/ release tag
