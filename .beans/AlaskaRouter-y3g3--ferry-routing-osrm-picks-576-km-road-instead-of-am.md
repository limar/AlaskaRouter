---
# AlaskaRouter-y3g3
title: Prefer ferries (Valhalla with use_ferry=1.0 → AMHS sailings render correctly)
status: draft
type: bug
priority: high
created_at: 2026-06-01T16:13:53Z
updated_at: 2026-06-01T16:42:53Z
blocked_by:
    - AlaskaRouter-2l0i
---

## Symptom

User reports: a trip with Valdez → Whittier returns a ~576 km overland route. The expected best path is the Alaska Marine Highway System (AMHS) car ferry across Prince William Sound (~80 NM / ~6 h scheduled). This is high-priority basic planning functionality for Alaska — many real itineraries depend on AMHS legs.

## Root cause (working hypothesis, to verify)

1. We hit the public OSRM demo (`router.project-osrm.org`) with the stock `driving` car profile.
2. The stock car profile assigns ferries a fixed slow speed (~5 km/h) unless the OSM ferry way carries an explicit `duration=PTxxHxxM` tag.
3. The cost function minimizes TIME. Valdez ↔ Whittier via ferry at 5 km/h modeled-speed ≈ 26 h. The road alternative (Glenn Hwy + Seward Hwy via Anchorage) ≈ 576 km at ~80 km/h ≈ 7 h. The road wins by the cost function — even though in reality the ferry sailing is 6 h and the user wants it.
4. Conclusion: this isn't an OSM data bug or an OSRM bug. It's a cost-function/preference mismatch. The router can't know the user's real-world ferry preference from waypoints alone.

To verify before designing the fix, capture a single OSRM response for Valdez → Whittier and check (a) whether the chosen route includes any `route=ferry` legs, (b) whether OSM has the AMHS Valdez↔Whittier sailing tagged with a duration. Both can be checked in <5 min once online.

## Solution space (no decision yet — discuss with user)

A. **Manual per-leg ferry mode** — leverage the existing `TravelMode.ferry` enum (Waypoint.modeRaw already supports it). User long-presses a leg or toggles the destination stop to ferry mode; the routing pipeline skips OSRM for that leg and renders a great-circle / known polyline. Offline-clean.
B. **Bundled AMHS port lookup + ferry leg polylines** — small GeoJSON of all AMHS terminals + sailing routes shipped in the app. When the leg's endpoints match two AMHS ports, offer "use ferry" with the bundled geometry + AMHS-published distance/duration. Offline-clean.
C. **Auto-suggest ferry when appropriate** — when both endpoints are at known AMHS ports AND the road route is much longer than the sailing, prompt: "Take the ferry from Valdez to Whittier?" Yes/no on a single tap. Offline-clean.
D. **Different routing backend (ORS / Valhalla / GraphHopper)** — they support `use_ferry` preference and known ferry duration. Heavier integration; ORS requires API key + has quotas; Valhalla is v2 anyway.
E. **Custom OSRM profile self-hosted** — recompile car profile with boosted ferry preference, host our own. Heavy infra. Discard.

## Recommendation (proposed, to confirm)

Stack A+B+C as one feature:
- Schema: extend `RouteSegment` (or add a parallel `ManualSegment`) carrying `mode: TravelMode`. The segment cache already keys on (from, to) — perfect fit.
- Bundle a tiny `amhs-routes.geojson` (~20 KB) with terminal coordinates and per-sailing distance/duration. Source: AMHS published schedule.
- UI: when the user adds a stop at (or very near) an AMHS terminal and the previous stop is also a terminal, show "Take ferry from X to Y?" suggestion. Tap → mark the leg as ferry → cache stores the bundled polyline as the segment's geometry → ribbon renderer can render ferry legs distinctively (dashed-blue / boat icon).
- Manual override always available: user can toggle any leg to `.ferry` mode on demand without endpoint matching.

This works **offline** (no API), composes with the per-segment cache we just shipped (un6b), reuses the existing `TravelMode.ferry` slot, and degrades gracefully (if the leg's endpoints aren't AMHS terminals the suggestion just doesn't appear).

## Open questions for discussion

1. Should we also model ferry SCHEDULES (departure times) in v1, or just geometry + duration? Schedules need bundled data refresh; geometry is static for years.
2. Render style for ferry legs — distinct color? Dashed? Boat marker?
3. AMHS-only initially, or also bundle other Alaska ferry operators (IFA Inter-Island)?
4. Block the road-route fallback when a leg is marked `.ferry`, or keep it as an "alternative" the user can flip back to?

## TODOs (deferred until direction is agreed)

- [ ] Verify OSRM response for Valdez → Whittier to confirm the cost-function hypothesis.
- [ ] Acquire AMHS published distance/duration for each sailing (their PDF schedule has it).
- [ ] Design + decide on the per-leg mode UI affordance.
- [ ] Implement.


---

## Findings (research, 2026-06-01)

Switching to **Valhalla** via the public FOSSGIS demo at `https://valhalla1.openstreetmap.de` solves the Valdez→Whittier case with no per-leg manual marking required.

### Probe results

| Probe | Result |
|---|---|
| Valdez (61.13083, -146.34833) → Whittier (60.77361, -148.68333), `use_ferry=1.0` | **145.5 km, 6h 7m, `has_ferry: true`**, instruction text: "Take the Alaska Marine Highway - Whittier-Valdez Ferry" |
| Same coordinates, no `use_ferry` | 487 km, 7h 4m, road via Glenn Hwy + AK 4 |
| 10 rapid requests | All HTTP 200, 0.3–0.4 s each |
| 60-location request | HTTP 400, `"Exceeded max locations: 20"` (hard limit) |
| `format=osrm` response | Works; OSRM-compatible response shape |

AMHS Whittier-Valdez sailing is properly tagged in OSM with a real `duration=` value, so Valhalla's ferry cost is realistic.

### Public FOSSGIS Valhalla terms (verbatim where possible)

- Rate limit: **1 call / user / sec, 100 calls / sec total** (sources: [Discussion #3373](https://github.com/valhalla/valhalla/discussions/3373), [PR #3444](https://github.com/valhalla/valhalla/pull/3444))
- Hard max **20 locations per `/route` request** (empirically confirmed via probe)
- Required: `X-Client-Id: <appname>` header for published apps + heads-up on the GitHub Discussions thread
- "Won't be usable for any production service for third parties" — informal but explicit
- No formal TOS doc, no commercial-use ban, no daily cap, no API key

### Maps to our phases

| Phase | Verdict |
|---|---|
| Personal dogfood | Fully fine |
| OSS / TestFlight beta | Fine, with `X-Client-Id` + a Discussions ping |
| App Store at scale | Plan a backend swap (self-host Valhalla on a $10/mo VM, paid Valhalla provider, or bundle Valhalla offline per [AlaskaRouter-p6ow]) |

### Implementation plan (parking under this bean)

This bean is now **blocked by [AlaskaRouter-2l0i]** because Valhalla's 20-location hard limit makes the partial-fetch chunking design load-bearing rather than just an optimization. Once 2l0i lands, Valhalla rolls in cleanly.

1. New `Routing/ValhallaProvider: RoutingProvider`. POST `https://valhalla1.openstreetmap.de/route` with `format=osrm`, `costing=auto`, `costing_options.auto.use_ferry=1.0`, `X-Client-Id: dev.alaskarouter.AlaskaRouter`.
2. Make `ValhallaProvider` the default in `RootView`. Keep `OSRMProvider` available as a manual fallback.
3. Decoder reuse: `format=osrm` returns OSRM-shape JSON (`routes[0].legs[].steps[].geometry`); minor patches to the existing decoder.
4. Cache invalidation for the engine swap: add `routerVersion: Int = 0` to `RouteSegment` (and a parallel `Trip.snappedRouteRouterVersion`). New build sets the constant to 1; older cache rows auto-miss and re-fetch via Valhalla. Existing trips silently re-route on next open / edit.
5. Render ferry legs distinctively (TBD — likely teal-blue + boat midpoint marker).
6. Post a heads-up on Valhalla [Discussion #3373](https://github.com/valhalla/valhalla/discussions/3373) before any non-personal distribution.

### Open decisions still pending (from prior discussion)

1. `X-Client-Id` value — proposed `dev.alaskarouter.AlaskaRouter` (matches bundle id).
2. `use_ferry` value — proposed 1.0 (Alaska-skewed). 0.7 would be milder.
3. Cache-version bump UX — silent re-fetch on first open vs one-time notice. Proposed silent.
4. Ferry leg render style — to confirm at impl time.
