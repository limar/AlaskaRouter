---
# AlaskaRouter-rvzg
title: Google Maps export lands on the wrong place (or nothing)
status: in-progress
type: bug
priority: high
created_at: 2026-07-27T21:34:45Z
updated_at: 2026-07-27T22:46:41Z
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

## Sharpened analysis (2026-07-27) — correctness first, name second

The user pushed back on option (a) (bare coordinates): if Google's own record for a place sits at coordinates that differ from OSM's — likely common for remote Alaska — the pin arrives with **no description**. Functional for routing, opaque to read. Fair.

The resolution is a priority order rather than a single pick:

**Position correctness is non-negotiable; the name is cosmetic.** A wrong name is a cosmetic loss. A wrong *position* sends the user driving somewhere wrong, which for an expedition planner is the one unacceptable failure. So any name-first form is disqualified unless it proves near-perfect — and the field already showed it isn't.

That makes the target: *coordinate-anchored, with the name riding along if Google will take it.*

### Candidates, ranked
- **G1 — `comgooglemaps://?q=<lat>,<lon>(<name>)`.** The parenthesised-label form from the `geo:` URI convention. If iOS Google Maps honours it, this wins outright: exact position AND our label. Undocumented for the iOS scheme — must be tested, cannot be reasoned about.
- **G2 — `https://www.google.com/maps/search/?api=1&query=<lat>,<lon>`.** Google's documented universal link. Guaranteed-correct position, opens the app when installed. The user's "no description" objection applies. This is the safe floor.
- **G3 — today's form with zoom 14 → 17.** Kept only as a control, to confirm the tighter viewport doesn't rescue it.
- **G4 — `query=<name>, <adminArea>, AK`.** Name-first with the borough we already display. Best-case gives the rich Google card; worst case is a confidently wrong location. Only viable if it proves near-perfect.
- **Rejected: Places API `query_place_id`.** Gives a guaranteed-correct named card, but needs an API key, network and per-call cost, and breaks the offline-first stance. Note for v2+ only.
- **Fallback if G1 fails and G2 really is bare: reverse-geocode to a postal address** via `CLGeocoder` before hand-off. Costs a network round-trip on a currently-instant action, and rural Alaska addresses are poor. Third choice.

### Apple Maps may already be correct
`PlaceShareURL.swift:98` uses the same `q=<name>&ll=<lat>,<lon>` shape that failed for Google, so it looked equally suspect. But Apple **documents** that `q` acts as a *label* when the position is already pinned by `ll`, rather than as a search query. If that holds on device, Apple has been doing the right thing all along and only Google needs changing — and G1 is simply the Google equivalent of it. Included in the bake-off to confirm rather than assume.

### On-device bake-off
The Simulator has none of these apps, so this can only be judged on the phone. Built a tappable page covering 5 waypoints × the candidate forms, each chosen to break differently:

| case | why it's there |
|---|---|
| Farthest North Spruce | OSM-only; Google has no record — tests a worthless name |
| North Pole | trip stop 1; text search wants Santa — the wrong-place test |
| Coldfoot Camp | famous truck stop Google *does* know — where a name could beat a coordinate |
| Galbraith Lake Campground | remote; Google's record may sit far from the OSM coord — the drift case |
| unnamed dropped pin | already coordinate-only; confirms nothing regressed |

Harness: https://claude.ai/code/artifact/8f891634-4a4f-45f2-9768-b279f279e1bf

## Todo
- [x] Spike: build the on-device URL-form bake-off across the hard cases
- [] User runs it on the device; record which form wins per app
- [ ] Implement the winner in `PlaceShareURL`; re-check Apple in the same pass
- [ ] Update `PlaceShareURLTests` so the chosen format is locked
- [ ] Field-verify on the real device
