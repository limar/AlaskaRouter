---
# AlaskaRouter-cv05
title: Display Arctic Circle and Equator on the map
status: todo
type: feature
priority: low
created_at: 2026-05-20T20:20:13Z
updated_at: 2026-05-31T14:09:44Z
parent: AlaskaRouter-xtua
---

Draw the Arctic Circle (lat 66.5634°N) and the Equator (lat 0°) as gentle latitude reference lines on the basemap. The Arctic Circle is iconic for Alaska — crossing it is a photo-stop landmark for any northbound trip — and the Equator gives global orientation when zoomed all the way out. Both should feel like atlas lines: thin, dashed, labeled, low-key.

## Why

The Arctic Circle (66.5634° N) is the single most iconic latitude landmark for any Alaskan trip — it's where every Dalton Highway traveler stops to photograph the "Arctic Circle" wooden sign and decide whether they're committing to Deadhorse or turning back. Showing it on the map turns it from "a place name to remember" into "a line you can see, follow, and orient to."

The Equator pairs naturally — it's the global orientation cue when fully zoomed out (z=0..3), the moment when you can't read any place labels.

## Likely implementation

Both lines are constants, never change. Encode as a small GeoJSON `LineString` (Arctic Circle: full 360° at lat 66.5634; Equator: full 360° at lat 0) and load via a vector source like the anchor labels.

Style as `LineStyleLayer`:
- `line-dasharray`: e.g. `[6, 4]` — atlas-style dashed
- `line-width`: thin (0.8pt at low zoom, no need to scale up)
- `line-color`: warm sepia for Arctic Circle (`#7a5e2b`), softer grey for Equator
- `line-opacity`: zoom-interpolated, fade in around z=2 and stay visible

Plus a `SymbolStyleLayer` for labels:
- `text-field`: "Arctic Circle" / "Equator"
- `symbol-placement: line` (text follows the line itself)
- `text-letter-spacing: 0.25`, small caps optional

## Considerations

- Globally drawn — the Arctic Circle is interesting around Alaska too, not just at the precise crossing. Lines should not be Alaska-only.
- Tropics (Cancer / Capricorn) and Antarctic Circle would naturally follow — defer to a follow-up if there's appetite.

## Checklist

- [ ] Author `lat-lines.geojson` with the two LineStrings
- [ ] Add vector source + LineStyleLayer to `style-base.json`
- [ ] Wire `__LAT_LINES_URL__` substitution in `ExpeditionMapView`
- [ ] Verify dashing reads at z=2, 4, 6, 10
- [ ] Verify the "Arctic Circle" label sits gracefully when crossing the Dalton Highway area
