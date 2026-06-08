---
# AlaskaRouter-55pn
title: Share place to external maps apps (Google/Waze/Apple/Maps.me)
status: in-progress
type: feature
priority: normal
created_at: 2026-06-08T14:47:58Z
updated_at: 2026-06-08T15:00:43Z
---

Export/share a place (waystop, POI, or dropped pin) to external maps/navigation apps for discovery (photos/ratings) and navigation.

## Approach
- Named entity (POI / named waystop) -> send name + center coords. Discovery apps (Google/Apple) surface rich place card; nav apps (Waze/Maps.me) ignore name, use coords.
- Unnamed (dropped pin) -> coords only.
- No client-side verification / no Places API: the coordinate center-bias IS the foolproofing. Instant (build URL + openURL).
- Apple Maps can optionally do MKLocalSearch verify-then-open later (Apple-only polish), degrades to coords offline.

## App matrix
- Google Maps: discovery, name+center, rich card. comgooglemaps:// + https fallback.
- Apple Maps: discovery, name+ll, rich card. maps.apple.com / MKMapItem.
- Waze: navigation, coords (waze://?ll=..&navigate=yes) + https waze.com/ul fallback.
- Maps.me: navigation/offline, coords + label (mapsme://map?v=1&ll=..&n=..).

## UI
- Share = small icon button, trailing-right in callout action row, uniform across all callout variants.
- Spatial grammar: LEFT slot = trip-membership action (Add to trip <-> Remove), RIGHT slot = Share (constant).
- Remove other Left/Next/Prev browsing buttons from waystop callout.
- Single-row icon+label buttons (kill stacked icon-over-label) to halve vertical height.
- Remove styled as ghost-red (de-emphasize destructive) while Add-to-trip stays solid orange.
- Custom app-chooser sheet (Google/Waze/Apple/Maps.me), grey out / hide apps not installed via canOpenURL.

## Testing
- Pure URL-builder functions (name?, coord, app) -> URL, unit-tested for every app x (named/unnamed).
- Simulator: Apple Maps end-to-end + https fallbacks via Safari. xcrun simctl openurl booted.
- Real device: native third-party handoffs + installed/not-installed chooser.
- Info.plist: LSApplicationQueriesSchemes must list comgooglemaps, waze, mapsme.

## Todo
- [x] Pure URL-builder + unit tests (formats locked)
- [x] Info.plist LSApplicationQueriesSchemes
- [x] App-chooser sheet (installed detection)
- [x] Callout redesign: Share trailing, remove Prev/Next, single-row buttons, ghost-red Remove
- [x] Wire Share into place + waystop callouts
- [ ] Device test matrix

## Progress (this session)

Implemented and verified on Simulator:
- PlaceShareURL.swift: pure (MapApp, SharePlace) -> URL builder. 10 unit tests PASS, formats locked.
- Info.plist with LSApplicationQueriesSchemes (comgooglemaps/waze/mapsme); merged via INFOPLIST_FILE + GENERATE_INFOPLIST_FILE. Build validates it.
- ShareToMapsSheet.swift: custom chooser, canOpenURL availability, hides uninstalled. On Simulator shows Apple Maps only (expected).
- ShareCalloutButton: shared trailing share control.
- PreviewCallout: [Add to trip | Share] row.
- StopCallout: removed Prev/Next, single-row [ghost-red Remove | Share]; deleted dead actionItem/itemColor + RootView Prev/Next handlers.
- RootView: SharePresentation wrapper + .sheet(item:).
- Apple Maps https handoff verified end-to-end via xcrun simctl openurl (opens Maps).

Remaining: device test matrix for the 3 native handoffs + visual confirm of redesigned callouts on a real iPhone.
