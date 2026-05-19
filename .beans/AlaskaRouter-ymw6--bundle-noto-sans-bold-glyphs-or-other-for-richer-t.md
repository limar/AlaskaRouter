---
# AlaskaRouter-ymw6
title: Bundle Noto Sans Bold glyphs (or other) for richer typography
status: todo
type: task
priority: low
created_at: 2026-05-19T09:14:43Z
updated_at: 2026-05-19T09:14:43Z
parent: AlaskaRouter-xtua
---

Currently only Noto Sans Regular is bundled (AlaskaRouter/glyphs/Noto Sans Regular/). Requesting any other font in style or DSL textFontNames causes MapLibre to fail rendering the entire symbol layer (root cause of AlaskaRouter-amh7).

If we want bolder/lighter weight distinction or different families later (selected stops, headlines, basemap-style overrides), need to bundle additional PBFs.

Options:
- Generate Noto Sans Bold PBFs (https://github.com/maplibre/font-maker)
- Use a single weight everywhere (current approach) and lean on size/halo/color for hierarchy
- Switch glyph engine to local-ideographs for CJK + bundled Latin

Pick when typography needs change. Until then, every text-using layer MUST stick to 'Noto Sans Regular'.
