---
# AlaskaRouter-rvzg
title: Google Maps export lands on the wrong place (or nothing)
status: todo
type: bug
priority: high
created_at: 2026-07-27T21:34:45Z
updated_at: 2026-07-27T21:36:47Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. Exporting a waystop to Google Maps essentially never works: Google searches our OSM-flavoured name, finds nothing, or finds a same-named place on another continent.

## Cause — `AlaskaRouter/Sharing/PlaceShareURL.swift:107`
```swift
return make("comgooglemaps://?q=\(enc(name))&center=\(lat),\(lon)&zoom=14")
```
The design comment (lines 3-9) assumes `center` biases the search enough to be "foolproofing". The field says otherwise: in Google's scheme `q` is a **search query** and `center` is only a *viewport hint* — it does not constrain the result set. Our names come straight from OSM ("Farthest North Spruce", "Galbraith Lake Campground"), which are frequently not Google Places entities at all.

The same `name + ll` pattern is used for Apple Maps (line 98) and should be re-checked in the same pass — it may be masked rather than correct.

## Options to evaluate
- **(a) Coordinate as the query, official universal link** — `https://www.google.com/maps/search/?api=1&query=<lat>,<lon>`. Documented, opens the app when installed, drops an exact pin, and Google *itself* labels the card with the nearest known place. This is what "share a pin" produces. Not opaque in practice — the user sees a named card, not raw digits.
- **(b) Native scheme, coordinate query** — `comgooglemaps://?q=<lat>,<lon>&zoom=15`. Same idea, app-only.
- **(c) Coordinate + label** — the `geo:`-style `q=<lat>,<lon>(<label>)` form. Would be ideal (exact pin *and* our name); needs verification that iOS Google Maps honours the parenthesised label rather than treating it as text.
- **(d) Resolve a real `place_id` via Google Places API** — accurate, but needs a key, network and per-call cost, and breaks the offline-first stance. Recommend rejecting for this round; note it as v2+ if (a)-(c) disappoint.

## This needs an on-device bake-off, not a desk decision
Google/Waze/Maps.me are absent from the Simulator, so URL forms can only be judged on the phone with the real apps installed. Build a throwaway harness screen that fires each candidate form at a few *hard* Alaska waystops (an OSM-only name; a name that also exists in the lower 48; a dropped pin) and record what each app actually shows.

`Tests/PlaceShareURLTests.swift` locks the current formats — it updates with whatever wins.

## Todo
- [ ] Spike: on-device URL-form bake-off across the hard cases (Google first, then re-check Apple)
- [ ] Agree the winning form per app
- [ ] Implement + update PlaceShareURLTests
- [ ] Field-verify on the real device
