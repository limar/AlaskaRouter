---
# AlaskaRouter-tymg
title: Share-sheet 'Open in' tile shows unmasked square doc icon (sharp white corners)
status: completed
type: bug
priority: normal
created_at: 2026-06-14T19:47:30Z
updated_at: 2026-06-15T08:14:56Z
---

The share-sheet apps-row "Open in AlaskaRouter" tile shows SHARP 90-degree white corners, while every other tile is rounded. This is the document-handler tile, NOT the document preview (top, which is our map via SharePreview) and NOT the home-screen app icon (masked, fine).

## Hard data
- We declare CFBundleTypeIconFiles -> TripDocumentIcon (added in h113).
- TripDocumentIcon-320.png is opaque WHITE-square (254,254,254, no alpha) — made by resizing the white-corner AppIcon.
- Sharp 90-degree corner = the tile is shown UNMASKED. So it is rendering the document icon as-is, not the system-masked app icon.

## Hypothesis
The handler tile renders CFBundleTypeIconFiles unmasked. App icons get the system squircle; document icons do not (shown ~as-is). Reusing a square app-style image as the doc icon = square white corners in the tile.

## Experiment A (this bean)
- [ ] Remove the CFBundleTypeIconFiles declaration from Info.plist (keep the TripDocumentIcon PNGs — SharePreview fallback still uses one). Rebuild.
- [ ] Verify: apps-row tile should fall back to the system-masked app icon -> rounded. (Needs a tap to open the share sheet — user eyeball or computer-use.)
- [ ] If rounded: confirmed. Decide whether a branded .akrtrip FILE icon is worth pursuing via alpha-rounded doc icon (B) or a QuickLook thumbnail extension (C). If not, ship without a custom file icon.

## Notes
- Web docs (CFBundleTypeIconFile, archived file-types guide, forums) were contradictory on doc-icon masking/alpha; conclusion rests on our own measured data + the sharp-corner observation.

## RESULT — hypothesis WRONG, root cause identified
Diagnostic: app-icon corners painted MAGENTA, doc-icon corners CYAN. The tile showed MAGENTA => the share-sheet "Open in" handler tile renders the APP ICON, not CFBundleTypeIconFiles. Experiment A (removing the doc icon) was therefore irrelevant. The white = the APP ICON own white corners, shown by this tile with little/no rounding (unlike the masked home screen).

Open question: is the near-square/unmasked tile rendering a SIMULATOR artifact (sim LaunchServices/handler-icon rendering is unreliable) or real on device? Needs a check on a real iPhone. Regardless, the app icon SHOULD be full-bleed (no white) per Apple HIG — the real fix for the white.

## RESOLUTION — Simulator-only artifact, no fix needed (2026-06-14)
Verified on a real iPhone 16 (iOS 26): the export share sheet is correct.
- The document PREVIEW (per-trip map, AlaskaRouter-56kj) renders beautifully, properly rounded.
- AlaskaRouter does NOT appear in its own apps row on device — so the "white sharp-cornered self tile" AND the earlier "why export to ourselves?" concern were BOTH iOS Simulator behaviours, not real.

Root cause of the whole saga: the iOS Simulator mis-renders the share-sheet "Open in" handler tile (unmasked app icon with its baked white corners) and also lists the app as a handler of its own type. A real device does neither.

What this cost us (the studies): several wrong theories (mask-radius mismatch; CFBundleTypeIconFiles document icon). The decisive step was a colour diagnostic — app-icon corners MAGENTA vs doc-icon corners CYAN — which showed MAGENTA, proving the tile uses the app icon, and ultimately that the artefact is Simulator-only.

LESSON: verify icon / share-sheet / LaunchServices rendering on a REAL DEVICE; the Simulator is not a reliable surface for it. The app icon itself needs no change (full-bleed opaque square, system-masked, looks great on device). Diagnostic changes discarded; no code change shipped.
