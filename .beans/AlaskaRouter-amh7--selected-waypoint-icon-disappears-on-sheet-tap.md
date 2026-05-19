---
# AlaskaRouter-amh7
title: Selected waypoint icon disappears on sheet-tap
status: in-progress
type: bug
priority: high
created_at: 2026-05-19T07:16:29Z
updated_at: 2026-05-19T07:16:29Z
parent: AlaskaRouter-xtua
---

Tap a stop in the trip bottom sheet -> map focuses -> the selected (sobresaliente, 60pt) icon vanishes. Tap another stop -> the previously selected reappears with default style, new one loses its icon.

Root cause: MapLibreSwiftDSL keys icon registration by UIImage.sha256() (Symbol.swift:59), which returns '' when cgImage?.dataProvider?.data is nil. UIGraphicsImageRenderer outputs hit that path -> both default + selected icons registered under name '' -> later clobbers earlier -> 'selected' layer renders the wrong (or no) image.

Fix in commit a6fb624 (WaypointIcons.swift): round-trip each icon through PNG so CGImage has a real CGDataProvider -> unique non-empty SHA256.

- [x] Identify root cause
- [x] Land fix in WaypointIcons.swift (PNG round-trip)
- [x] Build + install on simulator
- [ ] User verifies selected icon stays reliable across multiple sheet taps
