---
# AlaskaRouter-x3il
title: Nearest-snap for off-road waypoints (Valhalla hard-fails where OSRM nearest-snapped)
status: todo
type: feature
priority: normal
created_at: 2026-06-19T02:45:54Z
updated_at: 2026-06-19T02:45:54Z
---

Valhalla returns no-route (HTTP 400, error_code 442) for a waypoint that isn't on a road (e.g. the geographic center of Denali Park), where OSRM used to nearest-snap to the closest road point and still return a route. Investigate Valhalla knobs (costing_options.auto.search_filter, snap radius / location 'radius' & 'rank_candidates', or a pre-snap step) to route an off-road stop to the nearest road instead of dashing it.

REMINDER: discuss details + UI before implementing. Open questions to settle with the user first:
- Should an off-road stop be silently snapped, or visibly indicated (e.g. a connector dash from the stop to where the route actually starts)?
- What max snap distance is acceptable before we decline and keep it dashed?
- Does the stop pin move to the snapped point, or stay at the user's chosen location with the route diverging?
Spun off from AlaskaRouter-d0wt (batch-poisoning bug).
