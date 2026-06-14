---
# AlaskaRouter-56kj
title: App icon shows white corners in share-sheet apps row (alpha + baked rounding)
status: todo
type: bug
priority: normal
created_at: 2026-06-14T16:24:38Z
updated_at: 2026-06-14T16:24:38Z
---

The AlaskaRouter app icon renders with ugly white triangular corners in the iOS share-sheet "applications" row (the "Open in AlaskaRouter" tile). The document/file icon (TripDocumentIcon, used for the .akrtrip preview) looks correct — only the APP icon is affected.

## Diagnosis (confirmed)
`AlaskaRouter/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is 1024x1024 with `hasAlpha: yes` and baked-in rounded corners — the area outside the rounding is transparent. This violates Apple's rule that app icons be opaque, full-bleed squares with NO alpha and NO pre-applied rounding (iOS applies its own squircle mask). iOS composites the transparent corners onto white -> white slivers. Pre-existing; visible anywhere iOS masks the icon, surfaced by the export share sheet (AlaskaRouter-h113).

## Why the first fix attempt failed (h113 session)
Flattening AppIcon.png onto opaque cream did NOT fix it: at runtime the corners were still WHITE (not the cream fill), and the freshly-built bundle's app icon still reported `hasAlpha: yes`. So the edited source never reached the compiled asset — almost certainly actool asset-catalog caching in DerivedData / the single 1024 "universal" icon not being recompiled on an incremental build. Verification was also done against the springboard (blue wallpaper) which masked the issue instead of the share-sheet apps row (white bg). Both mistakes noted.

## Proper fix
- [ ] Replace AppIcon.png with a TRUE full-bleed opaque 1024x1024 icon: paper/terrain art extends into all four square corners, no alpha channel, no baked rounding. (The current art is a pre-rounded squircle on transparency — needs the source redrawn/extended, not just flattened.)
- [ ] CLEAN build (clear DerivedData / actool cache) so the new icon is actually compiled in; confirm bundled icon `hasAlpha: no`.
- [ ] Regenerate `AlaskaRouter/Resources/TripDocumentIcon-{320,64}.png` from the corrected icon for consistency (current ones are flattened-cream derivatives that happen to look fine).
- [ ] VERIFY in the actual share-sheet apps row on a light background (not the springboard), at full resolution — open Export from a trip and inspect the "AlaskaRouter" tile.

## Notes
- Document-icon branding (CFBundleTypeIconFiles + SharePreview, in h113) works and stays — this bean is only about the app launch icon.
