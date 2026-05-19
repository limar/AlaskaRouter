---
# AlaskaRouter-02pm
title: Route line color contrast on warm OpenTopoMap basemap
status: todo
type: bug
priority: normal
created_at: 2026-05-19T14:07:11Z
updated_at: 2026-05-19T14:07:11Z
parent: AlaskaRouter-xtua
---

The current per-block route line colors (TripColor: amber, teal, terracotta, sage, indigo, slate) are too muted against the warm OpenTopoMap raster basemap. Block lines render but at zoom 8–11 they nearly blend into the terrain, so multi-block trips don't visually pop the way the bean AlaskaRouter-7nxj design intends.

Verified during 7nxj step 3: with a separator splitting blocks, the routing layers ARE drawn (confirmed via diagnostic systemRed / systemBlue overrides — those were crisply visible), but the production palette doesn't have enough saturation / contrast.

Options:
- Bump block-line saturation (still warm/atlas-friendly) — replace amber 0.78,0.32,0.20 with a punchier red, teal with a richer cyan, etc.
- Increase line width (currently 4pt; try 5.5–6pt) and/or opacity (currently 0.95).
- Tighten the cream casing so the colored core is more dominant.
- Add a thin dark outline around the colored line (text-halo-style stroke).

- [ ] Sketch 2–3 palette/width variants, screenshot at zoom 8, 9, 11
- [ ] Confirm with user
- [ ] Roll out
