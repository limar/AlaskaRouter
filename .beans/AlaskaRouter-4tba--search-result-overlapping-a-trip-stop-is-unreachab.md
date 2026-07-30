---
# AlaskaRouter-4tba
title: Search result overlapping a trip stop is unreachable — stop always wins the tap
status: completed
type: bug
priority: high
created_at: 2026-07-30T17:42:55Z
updated_at: 2026-07-30T17:44:46Z
parent: AlaskaRouter-36of
---

Found in the field right after AlaskaRouter-35z7 (search-dot tappability) shipped. Searching "Camp" around Palmer returns a result sitting exactly on the Palmer trip stop; tapping it opens the **Palmer stop callout**, never the campground.

## Cause — my own tier ordering, working as designed

`ExpeditionMapView.dispatchKnownObject` ordered hits: trip waypoint → search result → ambient place. The comment justified it as "trip waypoints win because they're the user's own data". For a result that *exactly overlaps* a stop, that makes the result reachable from **nothing at all**: it can't be tapped, and the group-result badge offers no list view.

The asymmetry decides it: a stop stays reachable from the bottom sheet, and from the map as soon as the search is cleared. An overlapped result has no other route in. Losing the reachable thing beats losing the unreachable one.

## Fix — proximity, not a flat swap

When a stop and a result are both under the finger, the **nearer one wins**; on a tie the **result** wins.

A flat "results always win" was rejected: the result touch target is a deliberately generous 22 pt invisible circle (AlaskaRouter-35z7), much larger than a stop marker, so results would steal taps aimed at stops — badly at low zoom, where 22 pt spans kilometres.

## Verified on device
| case | result |
|---|---|
| result exactly on a stop (Palmer/Anchorage N. KOA on stop 35) | campground callout opens, "0.0 km from Palmer" |
| stop with a result nearby but not under it (Hatcher Pass, stop 37) | stop callout opens as before |

The "0.0 km from Palmer" line independently confirms the coordinates are identical — see the sibling data bean.

## Todo
- [x] Resolve stop-vs-result by proximity, tie to the result
- [x] Verify both directions on device

## Summary of Changes

`dispatchKnownObject` now takes the tap coordinate and resolves stop-vs-result by proximity, tie to the result. Ambient places still lose to both. Extracted `dispatchWaypoint` / `dispatchSearchResult` / `distance(from:to:)` so the branch reads as one decision rather than a fall-through chain.

Full suite green: 133 tests, 0 failures.
