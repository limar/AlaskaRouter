---
# AlaskaRouter-d0wt
title: Single unroutable waypoint poisons entire contiguous missing-run (batch routing all-or-nothing)
status: completed
type: bug
priority: high
created_at: 2026-06-18T05:16:58Z
updated_at: 2026-06-19T03:43:51Z
---

In the Alaska trip, stops 12..20 stay dashed/unrouted even though all but the Denali-center stop sit on routable roads. Root cause: SegmentPlanner.missingRuns batches all contiguous missing pairs into ONE routing request; the request is all-or-nothing (OSRM/Valhalla returns code != Ok if any single leg is unroutable), so one bad waypoint (Denali geographic center) marks the whole run pending. Creating a new trip without the bad stop routes fine because the run no longer contains it.

## Corrected analysis (provider = Valhalla, not OSRM)

Active provider is ValhallaProvider (RootView.swift:54). Two compounding bugs:

**Bug 1 — batch poisoning.** SegmentPlanner.missingRuns batches contiguous missing pairs into one run; chunked to <=10 waypoints (RoutingRequestLimits=10). The dead run (waypoints 9..18) is exactly 10 locations = a single Valhalla /route request including the unroutable Denali-center stop. Valhalla can't route a leg to that point so the WHOLE request fails -> all 9 pairs dashed, including the 8 routable ones (11..18).

**Bug 2 — no-route misclassified as rate-limit.** Valhalla returns HTTP 400 on no-route (ValhallaProvider.swift:105). RootView.swift:752 maps ALL RoutingError.http -> .rateLimited, so a permanent no-route advances the exponential backoff retry policy instead of the .noRoute path. The .server->.noRoute branch is effectively dead for Valhalla. Run never self-heals; every recompute re-sends the same 10-stop batch and re-400s.

## Proposed fix
- (Bug 2) Classify HTTP 400 + Valhalla no-route body (error_code 442 'No path could be found') as a distinct .noRoute outcome; keep 429 as rate-limit, 5xx as transport.
- (Bug 1) On a no-route outcome for a chunk with >1 pair, fall back to per-pair (or bisection) requests to salvage routable legs; only genuinely unroutable single pairs stay pending.
- Add a negative cache (per-pair 'unroutable at this geometry' marker, invalidated when the stop coords change) so we don't re-probe the dead leg on every recompute.

## Follow-up (separate)
Nearest-snap behavior: Valhalla hard-fails an off-road point where OSM/OSRM nearest-snapped to the closest road. Consider snap_radius / search_filter or a pre-snap step so a slightly-off-road stop routes to the nearest road instead of failing.

## Summary of changes (implemented, tests green)

Fix A — error classification:
- RoutingProvider.swift: new RoutingError.noRoute(reason:) case.
- ValhallaProvider.swift: on HTTP 400, decode the Valhalla error body and throw .noRoute when it's the no-path family (error_code 442 or message contains 'no path'); everything else stays .http. New static isNoRouteErrorBody(_:) helper + ValhallaErrorBody.
- RootView.swift task-group catch: .noRoute -> ChunkOutcome.noRoute; .http(429) -> rateLimited; other .http -> transport (previously ALL .http -> rateLimited, which sent permanent 400 no-routes into the backoff loop).

Fix B — bisection recovery:
- New Routing/SegmentRecovery.swift: split(_:) halves a run sharing the boundary waypoint; recover(_:snap:) adaptively bisects a no-route run, salvaging routable legs and isolating genuinely-unroutable legs to single pairs. Heavily commented incl. the simpler per-pair alternative.
- RootView apply loop: on a multi-pair .noRoute chunk, run SegmentRecovery.recover via provider.snap; write salvaged sub-runs to SegmentCache, leave .unroutable legs pending, treat .pending (transient) as retry-later.

Tests (all green, full suite 120 pass):
- Tests/SegmentRecoveryTests.swift (9): split geometry/offsets, Denali single-poison isolation to its 2 legs, two-poison, single-pair unroutable, transient-no-bisect, request-count <= per-pair.
- Tests/ValhallaProviderTests.swift (+4): no-route body classification (code, message-only, exceeded-max-locations negative, garbage negative).

Deferred: negative cache for confirmed-unroutable legs (so we don't re-bisect the Denali legs every recompute) — see follow-up task. Nearest-snap for off-road stops — see AlaskaRouter-x3il.

## Remaining
- [x] End-to-end verified on iPhone 17 Pro sim: whole trip dashes on cold load then steadily re-routes leg-by-leg, leaving only the 2 Denali legs dashed. Confirmed again after delete + re-import from file.

## Correction after failed retest — wrong error JSON shape (the actual reason it still dashed)

First fix attempt classified Valhalla no-route by the NATIVE body {"error_code":442,...}. But we request format=osrm, so Valhalla mirrors OSRM's error envelope: {"code":"NoRoute","message":"Impossible route between points"} (HTTP 400). So isNoRouteErrorBody returned false, the 400 fell through to .http -> .transport, and bisection recovery never ran. Verified live via curl against valhalla1.openstreetmap.de.

Fixed: ValhallaErrorBody now decodes BOTH shapes; noRouteOSRMCodes = {NoRoute, NoSegment}; message match on 'no path'/'impossible route'. New tests for the real OSRM shape + NoSegment + InvalidOptions(neg).

## Live ground-truth (curl) for the poisoned run (wp indices 9..18)
- leg 9->10  FAIL HTTP400 NoRoute  (touches Denali centre wp10 — genuinely unroutable)
- leg 10->11 FAIL HTTP400 NoRoute  (touches wp10)
- legs 11->12,12->13,13->14,14->15,15->16,16->17,17->18  ALL ROUTED
=> bisection will cache the 7 routable legs and leave only the 2 Denali legs dashed. Import (no wholeTrip blob in file; 31 segments restored) leaves exactly pairs 9..17 missing -> snap -> recovery.

Status: logic verified at every layer (21 unit tests pass; full suite green) + live API leg-by-leg. In-app visual not yet observed (CLI .akrtrip import hits the Files save panel; needs UI drive or user rebuild+reimport on a fresh store).
