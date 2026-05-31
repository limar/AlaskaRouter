---
# AlaskaRouter-jjxb
title: Z-axis ordering fixes for controls and labels
status: completed
type: bug
priority: high
created_at: 2026-05-27T10:28:37Z
updated_at: 2026-05-27T10:33:40Z
parent: AlaskaRouter-ka6b
---

Fix layering regressions around map chrome, search UI, and route highlight labels.

- [x] Move tweaks button into the same map-layer z-order as +/i and locate-me controls
- [x] Resize tweaks button to match map control button sizing without colliding with expanded search bar
- [x] Place route highlight below POI labels so labels remain readable
- [x] Run relevant simulator tests/build
- [x] Commit all changes

## Summary of Changes

Moved the tweaks button into the same early map-control ZStack layer as scale, locate, and zoom controls so search/results and sheets render above it. Resized the tweaks trigger to the same 44 pt circular control footprint. Inserted trip route highlight layers below style and POI label layers so labels remain readable above the route. Verified with the iPhone 17 Pro simulator test suite.
