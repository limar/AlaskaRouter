---
# AlaskaRouter-r1cf
title: 'HD zoom expansion: corridor region packs (z12-13) as optional downloads'
status: draft
type: feature
priority: normal
created_at: 2026-06-04T17:04:26Z
updated_at: 2026-06-04T17:04:26Z
parent: AlaskaRouter-ttvk
---

## Goal
More zoom detail than statewide z11, without bloating the bundled pack or blowing past practical storage.

## Cost analysis (hillshaded, scaling from the measured corrected z11 = 74,955 tiles ~655 MB PMTiles)

| Layer (statewide) | tiles | added size | render+export time* |
|---|---|---|---|
| z11 (shipping now) | 74,955 | ~655 MB | ~1.5 h |
| z12 | ~300k (4x) | ~2.6 GB | ~6 h |
| z13 | ~1.2M (16x) | ~10.5 GB | multi-day |

*DEM + contours are computed once and reused; only render + export scale ~4x per zoom level.

## GitHub Releases feasibility
- Limit is 2 GB PER FILE, unlimited files per release, and release assets do NOT count against repo size.
- So any statewide z12+ pack must be split into <2 GB assets. Corridor packs are naturally <500 MB each -> fine indefinitely at our scale.

## Recommendation
- v1: ship statewide z0-11 bundled (done).
- Do NOT bundle statewide z12+ (too big/slow, and most of Alaska is impassable/uninteresting for a road trip).
- For closer detail, build z12-13 ONLY over touring corridors (Anchorage<->Fairbanks + Dalton/Coldfoot, Denali/Parks Hwy, Kenai, SE) as OPTIONAL downloadable region packs. ~200-500 MB each; render a few hours total.
- 'Let the user choose which detailed layers to download' is the right UX, and it IS a bit geeky -> belongs in v2 with the regional-pack infrastructure.

## Depends on / reuses
- [[7yk7]] iCloud Drive regional pack distribution
- [[powi]] Multi-region pack management UI
- [[nv50]] Bundle manifest v2 schema
- [[rwbc]] Multi-region search

## Open questions
- Exact corridor bboxes + which to ship first (Dalton likely #1).
- Pack granularity: per-corridor vs per-zoom-per-corridor.
- In-app download/import UX vs manual Files import for v1.5.
