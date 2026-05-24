---
# AlaskaRouter-ymw6
title: Bundle Noto Sans Bold glyphs (or other) for richer typography
status: todo
type: task
priority: deferred
created_at: 2026-05-19T09:14:43Z
updated_at: 2026-05-23T17:35:50Z
parent: AlaskaRouter-xtua
---

Currently only Noto Sans Regular is bundled (AlaskaRouter/glyphs/Noto Sans Regular/). Requesting any other font in style or DSL textFontNames causes MapLibre to fail rendering the entire symbol layer (root cause of AlaskaRouter-amh7).

If we want bolder/lighter weight distinction or different families later (selected stops, headlines, basemap-style overrides), need to bundle additional PBFs.

Options:
- Generate Noto Sans Bold PBFs (https://github.com/maplibre/font-maker)
- Use a single weight everywhere (current approach) and lean on size/halo/color for hierarchy
- Switch glyph engine to local-ideographs for CJK + bundled Latin

Pick when typography needs change. Until then, every text-using layer MUST stick to 'Noto Sans Regular'.


## Findings (2026-05-23, deferred)

### Current state of the glyph stack

- Only `AlaskaRouter/glyphs/Noto Sans Regular/` exists, with **four** PBFs covering Latin + common punctuation:
  - `0-255.pbf`      Basic Latin + Latin-1 Supplement
  - `256-511.pbf`    Latin Extended-A
  - `8192-8447.pbf`  General Punctuation + Superscripts/Subscripts
  - `8448-8703.pbf`  Letterlike Symbols
- Every place that names a font hardcodes `"Noto Sans Regular"`:
  - `style-base.json` — 5 layers (`label-region`, `label-water`, `label-mountains`, `label-city`, `label-peak`)
  - `ExpeditionMapView.swift:432` — selected + default trip waypoint labels (`label.textFontNames`)
- Today's "selected vs unselected" trip stop hierarchy is **font-size only**: 14pt vs 13pt — a 1pt gap that's barely visible on device.

### How we'd add Bold

Three viable generation paths, in order of effort:

1. **`npx fontnik` locally** *(node is already installed)* — ~5 min:
   ```
   npm install -g fontnik
   build-glyphs NotoSans-Bold.ttf out/
   # then cherry-pick the same 4 unicode ranges Regular uses
   ```
2. **maplibre/font-maker browser tool** (https://maplibre.org/font-maker/) — upload TTF, download generated PBFs zip. Slowest network but zero local install.
3. **openmaptiles/fonts repo** — has source TTFs (`noto-sans/NotoSans-Bold.ttf`) but PBFs need to be generated via `node ./generate.js`. Same as path 1 but vendored.

Cherry-picking only Regular's 4 ranges keeps the bundle delta to ~50-200 KB total — negligible.

### Recommended Bold applications, ranked by visible payoff

| Layer | Today | With Bold | Visibility |
|---|---|---|---|
| **Selected waypoint's name** | Regular 14pt (vs Regular 13pt unselected) — 1pt gap | **Bold** 14pt — clear "this is selected" | ★★★★ (user is actively focused on this stop) |
| **`label-city`** for `place=city` (Anchorage, Fairbanks, Juneau) | Regular | Bold | ★★★ (improves mid-zoom hierarchy) |
| **`label-region`** | Regular | Bold | ★★ (only matters when zoomed way out) |

### Open question (decide when picking this back up)

Which subset of those three should v1 bundle? Selected-only is the smallest, highest-impact change. Settlement-tier requires a `case`/`step` expression on `place` in the style. Region is the smallest visible win but the biggest "atlas styling" upgrade.

### Why deferred

Other UI polish items take priority right now. Picking this back up is straightforward — none of the above is blocked on anything else; it's a one-session task once typography intent is locked.
