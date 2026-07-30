---
# AlaskaRouter-8w9l
title: Search-result dots look identical to the My Location puck
status: completed
type: bug
priority: high
created_at: 2026-07-27T22:40:00Z
updated_at: 2026-07-30T17:04:11Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. The group-search result markers read as the same object as the user's own GPS position — both are blue discs with a white ring.

## Cause — it is the same colour, by default
- `SearchResultStyle.swift:14` — "Index 0 is the default (a vivid electric blue…)", and `TweaksStore.swift:261` sets `searchResultColor = 0`.
- `WaypointIcons.makeUserLocation()` (`WaypointIcons.swift:157`) draws the puck in `rgb(0.10, 0.45, 0.95)` — the same blue family — with a white ring and a soft halo.
- `ExpeditionMapView.syncSearchResultLayer` draws each result as an `MLNCircleStyleLayer`: coloured disc + 2 pt white stroke. Same shape, same colour, same size range.

The two are deliberately *generic* for different reasons — the search set wants to read as one homogeneous "your matches" layer (AlaskaRouter-unir), the puck wants to read as "you" — and they collided.

## Options to discuss
- Recolour one of them. Cheapest, but blue-for-me is a strong convention worth keeping, so the search set should move — and it has a whole curated palette already (`SearchResultStyle`).
- Change the *shape* rather than the colour: a teardrop/pin silhouette for results vs a disc for the puck. Shape survives colour-blindness and small sizes better than hue.
- Give the puck its directional/halo treatment more prominently so "you" is unmistakable regardless of what else is on the map.

Related: AlaskaRouter-xyz1 below — the same markers are also nearly untappable, and a bigger/different marker may fix both at once. Worth designing the two together.

## Todo
- [x] Decide the visual language — colour does the work; shape was tried and failed (see below)
- [x] Implement — default palette index 0 → 4 (Violet)
- [x] Verify against the puck on screen at the same time, zoomed out and at 2.5 km scale

## Summary of Changes

Default `searchResultColor` changed from palette[0] "Electric blue" to **palette[4] "Violet"** — one line in `TweaksStore.Defaults`, still live-tunable from the Tweaks panel.

The diagnosis was exact, not approximate: palette[0] is `rgb(0.10, 0.45, 0.95)`, the *identical* RGB triple to the My Location puck's core, and both render as a disc with a white ring. "You" and "a search result" were literally the same marker.

**Violet was the user's call, against my magenta recommendation, and the user was right.** The worry that violet would merge with the purple route ribbon didn't survive contact with real renders — the ribbon is a wide translucent band, the dots are opaque with a 2 pt white stroke, and they read separately. Verified with the puck in frame at 2.5 km scale (violet dot at Moose Loop RV vs blue puck at Golden Heart Plaza) and zoomed out over the full result set.

**Shape variants are a dead end at this size.** A hollow-ring probe (white core, 3.5 pt coloured stroke) was rendered: at the dots' 4.5–11 pt radii the stroke swallows the core, so it reads as a solid borderless blob — and zoomed out, clustered blobs merge into an amoeba. Colour has to carry the distinction.

No migration needed: `TweaksStore` persists only on `didSet`, so any device that never touched the tweak picks up the new default on update.

## Process failure recorded (stale-build screenshots)

The colour-comparison round that nearly shipped magenta was **contaminated**: the ring-probe build was still installed when the puck comparisons were captured — the source had been reverted with `git checkout` but never rebuilt — so every "colour variant" screenshot was actually the rejected ring styling wearing different colours. That's what produced the ugly borderless blobs the user flagged. The committed code was never at fault. Lesson (now in memory): after reverting source, rebuild AND reinstall before capturing anything; a `git checkout` leaves the installed app silently running the probe.
