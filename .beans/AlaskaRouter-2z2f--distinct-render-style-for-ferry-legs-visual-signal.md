---
# AlaskaRouter-2z2f
title: Distinct render style for ferry legs (visual signal on the map)
status: todo
type: feature
priority: normal
created_at: 2026-06-01T17:02:04Z
updated_at: 2026-06-01T17:02:04Z
blocked_by:
    - AlaskaRouter-y3g3
---

With Valhalla preferring ferries via use_ferry=1.0 (landed in [AlaskaRouter-y3g3]), AMHS sailings now appear in the route — but they render as a normal solid trip-color ribbon. Visually indistinguishable from a road.

Worth: when a leg is a ferry, render it differently so the user sees at a glance "that part is by boat."

Options to pick from:
- Distinct color (teal-blue / wave-blue) overlay on the ferry leg
- Boat midpoint marker (SF Symbol `ferry.fill`) on long ferry segments
- Dashed-but-different cadence (NOT the same as pendingSnap's dashed)
- Animated wave underlay (cute but heavy)

Plumbing:
- Valhalla's per-step response includes a `mode` field and the AMHS steps are tagged. We need to surface "this leg is mostly ferry" up to RouteRibbon (new flag or new TripColor variant override).
- Detect at decode time in ValhallaProvider: for each leg, if any step's `mode == "ferry"` (or instruction matches the AMHS pattern), mark the leg.
- RouteRibbon grows a `mode: SegmentMode` enum or similar.
- Renderer adds a layer style for ferry ribbons.

Defer until y3g3 dogfooding tells us what reads best on the map.
