---
# AlaskaRouter-rvzg
title: Google Maps export lands on the wrong place (or nothing)
status: completed
type: bug
priority: high
created_at: 2026-07-27T21:34:45Z
updated_at: 2026-07-30T22:17:55Z
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

## On-device results (2026-07-27, user)

| case | G1 coord+label | G2 coord only | G3 name+center (shipped) | G4 name+borough |
|---|---|---|---|---|
| Farthest North Spruce | exact pin, sheet reads "Farthest North Spruce / provided by another app" | exact pin, DMS + decimal coords only | found **"Northernmost Spruce Tree"** — full Google POI, reviews, photos | **North Slope borough** — rich card, but *not the spruce* |
| North Pole | exact pin mid-town, sheet reads "North Pole / provided by another app" | as above | **(89.9999999, −135.0)** — the actual geographic North Pole | town boundaries selected, "North Pole, Fairbanks North Star, AK" |
| Coldfoot Camp | as above | as above | as above | as above |
| Galbraith Lake | as above | as above | as above | as above |
| dropped pin | — | DMS label + decimal coords | — | — |

**Apple confirmed correct, no change needed.** A1 put a labelled pin mid-town in North Pole with a street address and a Directions button; A2 showed "Farthest North Spruce" on both the pin and the sheet with a Dalton Hwy address. The documented `q`-as-label-when-`ll`-is-present behaviour holds. `PlaceShareURL.swift:98` stays as it is.

### Reading

- **G1 honours the parenthesised label.** This was the open question and the answer is yes. Exact position, our name on the card, in every case tested. Its only shortfall is a plain "provided by another app" card instead of Google's own POI data.
- **G3 (what we ship) is confirmed dangerous** — "North Pole" resolved to the literal geographic pole, 2,000+ km from the trip stop. Disqualified.
- **G4 is correct only for administrative entities.** It nailed North Pole (a town Google holds as a boundary) and failed the spruce, landing on North Slope Borough — an area of roughly 245,000 km². Rich card, wrong place. It fails on exactly the remote features a user most needs help locating.
- G2's coordinate card is as opaque as feared, and G1 strictly dominates it.

### The disagreement worth stating

The user's read was "G4 looks like the only well-working option". By the criterion agreed earlier — position correctness outranks card richness, because a wrong location sends you driving somewhere wrong — **G1 is the only form that is never wrong**, and it also solves the original objection: the pin is *not* anonymous, it carries our name.

G4's failure mode is quiet and severe: a rich, confident, authoritative-looking card for a place hundreds of kilometres from the waypoint.

No coordinate-anchored URL can produce Google's rich POI card without a Places API `place_id`. That is the real trade, and it cannot be bought with URL syntax alone.

## Decision (2026-07-27): go with the Places API

**The offline-first objection was wrong and is withdrawn.** Google Maps is useless without a connection, so at the moment the user taps "Open in Google Maps" they are, by definition, online. Refusing a network lookup to protect an offline case that cannot exist was a bad trade. A `place_id` is the only thing that yields an exact *and* named *and* rich card, and it is reachable.

Fallback if it proves infeasible: **G4**.

Note for the keyless path: whatever the app does with no key configured, my recommendation stays **G1** rather than G4 — G1 is never wrong, and G4 fails silently and severely on remote features (North Slope Borough for the spruce). Worth settling when stage 1 is built.

## Staging

**Stage 1 — keyless default.** The app must work with no key at all. Pick G1 (or G4) as the no-key behaviour, implement it, lock it in `PlaceShareURLTests`. Export stops being broken regardless of what follows.

**Stage 2 — Places lookup when a key exists.** On share, `findplacefromtext` / Places Text Search biased to the waypoint coordinate → take the top result within a sanity radius → hand Google `?api=1&query=<name>&query_place_id=<id>`. Falls back to stage 1 on no key, no network, no match, or a match outside the radius. **The radius check is the safety rail** — it is what stops a confident wrong card, which is exactly how G4 fails.

**Stage 3 — key onboarding worth the name.** "Paste your API key here" is the baseline, not the goal. Options to think through:
- A guided setup screen: what the key is for, what it costs (Places has a free monthly tier), a direct link to the right Google Cloud console page, then paste — the same act, but hand-held rather than presumed.
- Store it in the **Keychain**, not `UserDefaults`/`TweaksStore` where every other setting lives. A credential is not a tweak.
- Make the feature visibly optional: with no key the export still works, so the setup screen is an upgrade prompt, not a wall.
- Rejected: shipping a key in the app (extractable, abusable, and untenable for an OSS release) and running a proxy (hosting, plus the account/privacy surface we rejected for trip backup).

## Todo
- [ ] Stage 1: keyless default (settle G1 vs G4) + tests
- [ ] Stage 2: Places lookup with a coordinate sanity radius; fall back cleanly
- [ ] Stage 3: key onboarding + Keychain storage
- [ ] Field-verify each stage on the device

## Stage 1 shipped — G1 as the keyless default

`comgooglemaps://?q=<lat>,<lon>(<name>)` for a named place; unnamed dropped pins keep the existing coordinate-query form.

User chose **G1** over G4 for the keyless path. It is never wrong about position, and the on-device test confirmed the parenthesised label is honoured ("Farthest North Spruce / provided by another app"). What it does not get is Google's rich POI card — that needs a `place_id`, which is stage 2.

Also: `()` added to the encoded set in `placeQueryValue`, so a stop name containing a paren cannot close its own label early and leak the remainder into the URL as structure. Harmless for the other apps, which decode it back.

Tests updated (`PlaceShareURLTests`, 12 passing) — including a regression guard asserting the coordinate always leads the query, which is the specific thing that sent "North Pole" to the geographic pole.

Apple, Waze and Maps.me are unchanged; Apple was confirmed correct on-device.

## Todo
- [x] Stage 1: keyless default (G1) + tests
- [ ] Stage 2: Places lookup with a coordinate sanity radius; fall back cleanly
- [ ] Stage 3: key onboarding + Keychain storage
- [ ] Field-verify each stage on the device

## Stages 2 & 3 deferred past v2.0 (2026-07-30, user)

**Stage 1 shipped and closes the original bug** — export no longer lands on the wrong place. This bean is done for v1.1.

The Places API work (stage 2 lookup + stage 3 key onboarding) is **out of v1.1 scope and probably lands after 2.0**. Split out as its own bean. When picked up: ask the user for a valid Google API key (they say it is easy to obtain), and **check for an existing Swift SDK/framework for Google Places first** rather than hand-rolling the REST calls.
