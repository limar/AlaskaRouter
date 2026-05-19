---
# AlaskaRouter-amh7
title: Selected waypoint icon disappears on sheet-tap
status: in-progress
type: bug
priority: high
created_at: 2026-05-19T07:16:29Z
updated_at: 2026-05-19T08:26:48Z
parent: AlaskaRouter-xtua
---

Tap a stop in the trip bottom sheet -> map focuses -> the selected (sobresaliente, 60pt) icon vanishes. Tap another stop -> the previously selected reappears with default style, new one loses its icon.

Root cause: MapLibreSwiftDSL keys icon registration by UIImage.sha256() (Symbol.swift:59), which returns '' when cgImage?.dataProvider?.data is nil. UIGraphicsImageRenderer outputs hit that path -> both default + selected icons registered under name '' -> later clobbers earlier -> 'selected' layer renders the wrong (or no) image.

Fix in commit a6fb624 (WaypointIcons.swift): round-trip each icon through PNG so CGImage has a real CGDataProvider -> unique non-empty SHA256.

- [x] Identify root cause
- [x] Land fix in WaypointIcons.swift (PNG round-trip)
- [x] Build + install on simulator
- [ ] User verifies selected icon stays reliable across multiple sheet taps



## Spike findings (2026-05-19)

Built isolated spike at `spikes/C_icons/` to test the DSL's icon-registration pipeline with 9 distinct scenarios. Conclusions:

- **The icon registration / SHA256 hashing works correctly** — every UIImage has a unique non-empty hash after pngBacked round-trip. Verified via runtime style dump: both layers exist, both reference the right image names, both images are registered at correct sizes (44x44, 60x60).
- **The DSL renders multi-source / mixed-icon layouts correctly.** Tested 1+1, 8+8, 15+1, 16-distinct, and 15-DSL+1-raw-MLN. All variants render every icon, including in the 15+1 partition pattern that mirrors the main app.
- **The icon is NOT actually disappearing in the main app.** At zoom 8.5 the size difference between 44pt (default) and 60pt (selected) is too subtle to see in a portrait screenshot; the previously assumed empty slot was just the selected icon at small visual scale. Verified with zoom-11 A/B: selected stop renders an icon with a bolder ring, same general shape and palette.
- **What IS missing: the selected-style LABEL.** `textAllowsOverlap(false)` on the larger selected icon's halo likely suppresses the label placement against itself or against neighbor labels. The default stop's label ("Healy") shows; the selected version doesn't.

So this bug should be re-scoped to either:
(a) Make the selected style much more visually distinct (color, halo, glow) so the difference is obvious at all zoom levels — and figure out the label-suppression.
(b) Drop the selected style entirely and pick a different selection cue (camera centering, sheet-row highlight only).

Spike kept at `spikes/C_icons/` for future reference.
