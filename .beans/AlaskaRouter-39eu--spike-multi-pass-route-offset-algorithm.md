---
# AlaskaRouter-39eu
title: 'Spike: multi-pass route offset algorithm'
status: todo
type: task
priority: high
created_at: 2026-05-21T05:02:01Z
updated_at: 2026-05-21T08:57:01Z
parent: AlaskaRouter-xtua
---

Standalone spike rig to find the right offset algorithm for multi-pass route rendering. Two prior attempts in AlaskaRouter-3bot failed (per-point perpendicular self-intersects on curvy snapped polylines; uniform perpendicular doesn't track road curves). Build a focused matrix-style test bed on one stretch of road before re-attempting the production code.

## Why a spike

Two production attempts at multi-pass offset rendering in `AlaskaRouter-3bot` failed in characteristic, instructive ways:

1. **Per-point perpendicular offset** — self-intersects on curvy OSRM-snapped polylines. Loops at bends.
2. **Uniform perpendicular offset** — translated copies don't follow road curves; "ugly lines passing everywhere but along the road."

The class of problem is offset curves on real road geometry. Solving it in-place on the production code is risky: every iteration touches the same files, regressions ship to the iPhone, and the user sees broken visuals between attempts.

A spike isolates the experiment so we can iterate quickly with no risk to the main app.

## Plan (mirrors AlaskaRouter-3bot's "Spike" section)

### Step 1 — Define user expectations tightly

Surface and answer the questions in the parent bean BEFORE writing any code:
- Tracks road curves perfectly vs "parallel along the corridor"?
- Behavior at sharp bends / switchbacks?
- C⁰ vs C¹ continuity at waypoint joints?
- Color per pass vs per block?

These are taste decisions — needs user input. Don't code until they're decided.

### Step 2 — Sketch the geometry

For each candidate algorithm, write down what it computes, what it costs, and what its failure modes are:

- **MapLibre native `line-offset`** (GPU-level offset rendering). MLNLineStyleLayer exposes it; MapLibreSwiftDSL doesn't. Would need `unsafeMapViewControllerModifier` to add raw layers.
- **Per-pass single polyline + native offset**: one feature per pass instead of per segment.
- **Per-point perpendicular with K-window smoothing**: reduces but doesn't eliminate bend artifacts.
- **True offset curve algorithm** (Clipper, etc.): heavyweight C++ dep.

### Step 3 — Audit available knowledge

For each algorithm, check we have the data it needs:
- What does OSRM actually return for a multi-pass trip — single contiguous polyline or N separate ones?
- Does `line-offset` work on a polyline that revisits the same road?
- Without network, do we have ANY road shape, or just straight waypoint segments?

### Step 4 — Build the rig

`spikes/D_multipass/` — standalone target like the existing spikes (A_maplibre, B_fts5, C_icons). Contents:

- One Swift/SwiftUI app, single screen, one map view
- A fixed bundled polyline for ONE stretch (e.g. Cantwell→Healy, ~150 points from OSRM)
- Buttons / launch args to switch between scenarios:
  - 1 pass, 2 passes (same direction), 2 passes (opposite — out-and-back), 3 passes
  - Same color, two colors
  - Three preset zooms
- Side-by-side or toggleable rendering of the candidate algorithms

### Step 5 — Iterate until matrix matches expectations

Same 2×2×3 matrix from AlaskaRouter-3bot, but rendered for EACH candidate algorithm. Pick the winner by visual comparison.

### Step 6 — Port to production

Only after the spike resolves, port the winning algorithm to `AlaskaRouter/Data/TripSegments.swift` (or wherever it fits). Production refactor is the last step, not the first.

## Checklist

- [ ] Decide on user-expectation questions (Step 1) — discuss with user
- [ ] Write up candidate algorithms (Step 2)
- [ ] Audit OSRM/snap behavior + `line-offset` capability (Step 3)
- [ ] Bootstrap `spikes/D_multipass/` with project.yml + minimal MapLibre view
- [ ] Bundle a real OSRM polyline for the test stretch
- [ ] Implement scenario switcher (passes × colors × zoom)
- [ ] Implement candidate algorithms side-by-side
- [ ] Capture the matrix for each
- [ ] User picks the winner
- [ ] Port to production (unblocks AlaskaRouter-3bot)

## Out of scope

- Direction arrows (that's `AlaskaRouter-x605`)
- Color selection logic (current per-block coloring stays — just need parallel ribbons)
- Anything beyond the offset-rendering itself

## References

- `AlaskaRouter-3bot` — production bug this spike unblocks
- `AlaskaRouter-9axu` — original (now-naive) implementation
- `spikes/A_maplibre/`, `spikes/B_fts5/`, `spikes/C_icons/` — pattern to follow for the new spike target


---

## Visual model — locked

After a discussion round, the user's mental model is captured. **This is the spec the spike rig has to render.**

### Onion lanes (offset per pass)

Each pass moves perpendicular to ITS direction of travel. "Left" is relative to the pass's heading — so opposite-direction passes land on opposite sides of the road in absolute terms.

Offset (signed; "−" = pass's own left side):

| Pass | Direction rank | Offset |
|---|---|---|
| 1st forward | 0 | **−0.5 W** |
| 1st backward | 0 | **+0.5 W** |
| 2nd forward | 1 | **−1.5 W** |
| 2nd backward | 1 | **+1.5 W** |
| 3rd forward | 2 | **−2.5 W** |
| nth | n−1 | **(n − 0.5) × W × direction_sign** |

Road centerline is always empty (no pass sits on it) once there's ≥ 2 passes — the OSM-baked road label stays readable.

### Width unit W

"Cores well separated, washes overlap softly." Concrete W to be picked in the spike — sweep a few values and pick by eye.

**Architectural constraint**: highlight style is swappable (planned variants: highlighter pen, pencil pattern — neither has a "wash"). So W is parameterized **per style**, not a global constant.

### Funnel at waypoints — "all roads lead to Rome"

Each pass's polyline is the road shape with a per-point offset *envelope* that tapers from full W to 0 near every waypoint that pass touches.

- Far from any waypoint → full offset W (the onion lane)
- Within delta of a waypoint → smooth taper from W to 0
- At waypoint center → all passes converge to the same point (the waypoint center)
- After the waypoint → fans back out to the lane

**Delta = fixed value (≈ waypoint-icon diameter, ~30 pt at z=10).** Constant for all passes; outer onion layers therefore take steeper funnel turns. Spike will show whether that's acceptable or if delta needs to scale with offset.

**Taper shape**: smoothstep by default (C¹ continuous). Try linear / cosine in the spike too if smoothstep doesn't feel right.

### Color

Color follows the block (current behavior). No per-pass independent coloring.

### Branches

When a pass branches off the shared road, the onion thins out — the outermost layer just ends. Acceptable for v1. If the branch transition looks ugly, fix with a spline (defer).

### Sharp bends / switchbacks

Simplest approach for v1: just render, don't engineer for it.

**Possible v2 enhancement** (user's idea): emulate a geologist with a highlighter — at high-curvature stretches, *narrow* the offset locally so the ribbons squeeze closer together and stay readable. Don't build this now; revisit if v1 switchbacks look messy.

### Direction labeling

Implementation detail — the algorithm knows the waypoint sequence, so it knows each pass's direction.

## Open Q2/Q3/Q4 → all resolved

All design questions are answered. The spike is unblocked.

## Acceptance criteria for the spike

The spike rig should render the same 2 × 2 × 3 matrix (legs × colors × zooms) PLUS extras:

- Legs: 1, 2, 3, 4 passes
- Colors: same-block, two-block
- Zooms: 3 levels per scenario
- For each scenario, render variants of:
  - W width (e.g., 6 pt, 10 pt, 14 pt)
  - Funnel delta (fixed 30 pt as default; also try 20, 50)
  - Taper shape (smoothstep, cosine, linear)
- Highlight style stays wash+core for v1; structure allows swapping in highlighter / pencil later


---

## Investigation tree — ordered by dependency

The visual model is locked. What's still unknown is the *algorithm + data* path that gets us there. Five rings, each gating the next. Resolve in order, fully, before moving on.

### Ring A — API capability (gates everything; settle FIRST)

**A1. Does `MLNLineStyleLayer.lineOffset` actually work for our pipeline?**
`MLNLineStyleLayer` exposes `lineOffset: NSExpression?`. The renderer should handle offset perfectly on curves (it's the right answer if available). MapLibreSwiftDSL doesn't expose it, but we already use `unsafeMapViewControllerModifier` for the zoom cap (5h4y) — same pattern.

Sub-questions, each yes/no with a tiny ad-hoc test:
- A1.a — Can we add a *raw* `MLNLineStyleLayer` from the unsafe hook without breaking the DSL-built layers?
- A1.b — Does `lineOffset` accept a constant value (simplest case)?
- A1.c — Does it render correctly on a simple straight polyline (2 layers, ±14pt offset → 2 parallel lines)?
- A1.d — Does it render correctly on a curvy polyline (no self-intersection, no artifacts on bends)?
- A1.e — Does it work when the *same* polyline feature is referenced by multiple layers with different offsets?
- A1.f — Does `lineOffset` accept a data-driven expression (per-feature offset via feature property)? If yes, we can put all passes in one source and let MapLibre interpolate per feature.
- A1.g — Does it compose with `lineCap(.round)`, `lineJoin(.round)`, `lineDashPattern` so the wash+core layered look still works on top?
- A1.h — Does it interact correctly with `lineWidth(interpolatedBy: .zoomLevel, ...)` so the offset scales/holds across zooms predictably?

**Outcome of A**: one of three branches
- α — Native `lineOffset` works for everything we need. Algorithm becomes: build one polyline per pass + assign offset = `(rank + 0.5) × W × direction_sign`. Funnel still TBD (Ring D).
- β — Native `lineOffset` works for uniform sections but not the funnel taper. Algorithm becomes hybrid: long mid-sections via native offset, short funnel pieces via geometry-side coord shift.
- γ — Native `lineOffset` doesn't work for us (broken on iOS, can't reach from SwiftUI, breaks composition). Fall back to a geometry-side offset-curve algorithm (smarter than the two failed attempts — see Ring D).

### Ring B — Data audit (parallel to Ring A; gates Ring C)

What we *actually have* in the running app:

- **B1. What's in `snappedRouteCoords` for a multi-pass trip today?** Single contiguous polyline that retraces? N disjoint polylines? Need to print it from a live debug session to see.
- **B2. How does the OSRM call get made?** What request → what response shape? Does OSRM ever return separate route segments for retraced roads, or always one big polyline?
- **B3. What's the polyline density?** Average meters between snap points around (a) straight stretches, (b) bendy stretches (Atigun Pass), (c) waypoint vicinity. Determines whether the funnel envelope (~30pt = ~30m at z=10) covers enough points for a smooth taper.
- **B4. What happens at trip boundaries — waypoint coords vs nearest snap point?** Do they exactly coincide, or is the waypoint a few meters off the nearest snap-point? Affects how we anchor the funnel.

### Ring C — Pass identification (gates Ring D; depends on Ring B)

Given a sequence of waypoints + a snap polyline, define rigorously:

- **C1. What is a "pass"?** Working definition: a maximal sub-sequence of consecutive waypoints where the route is monotonic along the snap polyline. When `waypointIndex[i+1] < waypointIndex[i]`, the route has reversed → that's a pass boundary.
- **C2. How to assign each waypoint's index in the snap polyline?** Naïve nearest-snap-point fails for retraced roads (all visits to "Healy" pick the same snap-point). Need a *monotonic* assignment: each successive waypoint maps to the closest snap-point that's at least as far along the polyline as the previous waypoint's index (or earlier, if the route has reversed).
- **C3. How to assign each pass a direction relative to the shared road?** For two passes that share road segments, the first to traverse establishes "canonical direction"; subsequent passes get a + sign if same direction, − if opposite.
- **C4. How to assign each pass its rank within its direction?** Just order of appearance among same-direction passes on each shared road.

### Ring D — Offset envelope (gates rendering; depends on Rings A & C)

Per pass, compute the per-point offset that takes the polyline from "centered on road at waypoint" to "out at full W on the lane" and back.

- **D1. Taper window.** 30pt fixed at z=10 (~30 m on the ground). Tapers from offset 0 (at waypoint) to offset (rank+0.5)·W·sign (mid-leg).
- **D2. Taper shape.** Smoothstep by default. Try linear + cosine in the variant explorer.
- **D3. How does the taper interact with native `lineOffset`?** Native is a *layer-level* property — uniform along the line. If we go that route, the taper section needs to be:
  - (i) a separate short polyline feature with its own lineOffset value that interpolates between W and 0, OR
  - (ii) a geometry-side coord shift (we shift the coords directly for ~30pt around each waypoint).
- **D4. How do we render the wash+core look on offset lines?** Two layers per pass, same polyline source, same offset value, different widths/opacities/colors. Should "just work" with native lineOffset if A1.e is yes.

### Ring E — Variant exploration (the spike rig itself)

Only meaningful once Rings A–D are settled. The rig becomes a UI for sweeping the remaining tuning parameters:

- W width (e.g., 6 / 10 / 14 pt)
- Funnel delta (20 / 30 / 50 pt)
- Taper shape (smoothstep / cosine / linear)
- Scenarios: 1-4 passes × 1-2 colors × 3 zooms × straight road / curvy road / switchback
- Highlight style swap demo (wash+core → highlighter → pencil)

## Approach

Don't build the spike app yet. Start by answering Ring A inline in the existing codebase — tiny ad-hoc test branch, just enough to settle whether native `lineOffset` is available to us. That answer reshapes everything downstream.

Concretely:

1. **Step 1 — Ring A experiments** (small, isolated; in `ExpeditionMapView` behind a launch arg, or in a throwaway test view). Each sub-question A1.a..A1.h gets a yes/no with a screenshot or a console log. Maybe 1-2 hours of work. Outcome: which branch (α/β/γ) we're in.
2. **Step 2 — Ring B audit** (read OSRM-routed coords from a live multi-pass session, print sample stats). Maybe 30 min.
3. **Step 3 — Ring C algorithm** (paper sketch + unit tests; pure data transformation, no rendering). Maybe 1 hour.
4. **Step 4 — Spike rig** (only at this point). The rig implements the chosen algorithm from Step 1, with the Ring C pass-builder, and the Ring D envelope. The rig's UI handles Ring E sweep.
5. **Step 5 — Port to production.**

Total wall-clock estimate before we touch production: 4-6 focused hours, spread across several sessions.


---

## Ring A result — Branch α is DEAD

Tested `MLNLineStyleLayer.lineOffset` via `unsafeMapViewControllerModifier`.

**API capability**: ✓ all subquestions yes
- A1.a Raw MLNLineStyleLayer added from unsafe hook works alongside DSL layers
- A1.b lineOffset accepts NSExpression constant
- A1.c Renders correctly on simple straight polylines (parallel ribbons)
- A1.e Multiple layers can share one source with different lineOffset values
- A1.d **FAILS** on real OSRM-snapped curvy polylines

**A1.d failure mode**: native lineOffset uses per-vertex perpendicular extrusion at the GPU level. On tight bends where the local turn radius approaches or falls below the offset distance D, the offset polyline:
- Self-intersects on the concave side (loops)
- Bows out unbounded on the convex side (wide-arc artifacts)

This is geometrically inherent to offset curves of an arc: parallel curve at distance D has radius `r ± D`. When `D ≥ r`, the inner parallel is degenerate. No preprocessing fixes it.

**Preprocessing tested** (all on Parks Highway demo route, 3200 OSRM points):
- Subsample 1-in-10 → still dances
- Subsample 1-in-50 → cleaner on straight stretches, still dances at tight bends
- Moving-average window=5 → no visible change
- Moving-average window=30 → cleaner straight, still dances at tight bends
- Hand-built 4-point gentle arc → clean (control: algorithm works on tame data only)

**Strategic implication**: branches α (native only) and β (hybrid) are both dead. Native `lineOffset` cannot be the foundation of multi-pass rendering for our use case because real Alaska roads have bends tighter than the offset distance D we want to render.

## Branch γ is the only remaining path

We need a CPU-side offset-curve algorithm that:
1. Computes per-vertex perpendicular offset (cheap)
2. Detects self-intersections in the resulting polyline
3. Repairs them — typically by clipping inner-bend loops and joining with arcs on the outer side

### Implementation options

- **Clipper2**: industry-standard polygon clipping library, C++ source, has Swift wrappers. Heavyweight but solved-problem.
- **Hand-rolled algorithm**: feasible. Detect self-intersection via segment-pair intersection test; clip to convex hull of valid portions.
- **Resample + windowed-tangent**: cheaper approximation. For each output vertex, compute perpendicular from a TANGENT computed over a wider window (e.g., neighboring K=10 points). The wider window low-pass-filters the tangent direction, suppressing flips at bends. Imperfect but might be good enough visually.

## Next concrete step

Try option 3 (resample + windowed-tangent) first because it's the cheapest. If it works visually, we don't need a full Clipper integration. If it doesn't, we have a calibrated benchmark for what a proper algorithm needs to beat.

Move Ring A → CLOSED.
Move Ring D (offset envelope) → upgraded to "include full offset-curve algorithm".


---

## Decision — branch α with cores-only, native `lineOffset`, W/2 spacing

**APPROVED by user after iterative refinement in spike.**

Visual spec landing point:
- **Core only, no wash.** Wash creates a `{core, wash} × {color1, color2}` rainbow at multi-pass overlaps; not what the user wants. Cores-only gives a clean 3-zone reading: lane1 / lane2 / minimal overlap at corners.
- **Core width W = 10pt at z=10**, opacity 0.55. Solid stroke that reads as a highlighter mark.
- **Lane positions**: each pass moves `(rank + 0.5) × W × direction_sign` perpendicular to its travel direction. With W = 10pt:
  - 1st forward / backward: ±5pt
  - 2nd forward / backward: ±15pt
- **No funnel-to-waypoint** in this iteration. The user accepted 4-pass rendering through curves WITHOUT funnels: "production grade, totally usable, good looking, resembling human-drawn highlighting." The funnel from the locked spec is a nice-to-have, not a v1 blocker.
- **Native `MLNLineStyleLayer.lineOffset`** is the rendering mechanism. No coord-side shifting. The renderer handles curves at GPU level, with mild bend bowing that is **visually tolerable at production W and offset magnitudes** even on the real OSRM Parks Highway polyline.

## What's left to ship 3bot

1. **Ring C — Pass identification**. Algorithm to:
   - Parse the waypoint sequence into "passes" (maximal monotonic sub-sequences along the snap polyline)
   - Assign each pass a direction (forward = canonical, backward = reverse) and a rank within its direction
   - Compute its offset as `(rank + 0.5) × W × direction_sign`

2. **Production integration**:
   - Replace the coord-shifting code in `TripSegments.swift`
   - Wire each pass as ONE `MLNLineStyleLayer` with `lineOffset` set via `unsafeMapViewControllerModifier` (same pattern as the spike + the 5h4y zoom cap)
   - Per-pass color from the block model (color follows block — keep current behavior)

3. **Verification matrix** rerun: 2-pass / 3-pass / 4-pass × same/two color × z=8/9/10. We'll know we're done when this matrix matches the spike's quality.

4. **Cleanup**: strip the Ring A spike code from `ExpeditionMapView.swift` and the `spikeRingA` launch arg.

## Deferred (not v1)

- **Funnel-to-waypoint** — was in the locked spec, the user accepted v1 without it. Track as a polish follow-up. Best implementation path: render mid-segment with native lineOffset, render short funnel sections (last ~30pt before each waypoint) with geometry-side coord taper (short enough they don't self-intersect on bends).
- **Highlight style swap** (highlighter pen, pencil pattern) — already architecturally swappable since core-only, just a parameter change.

## Status update

- Ring A → **CLOSED, branch α viable**
- Ring B (data audit) → folded into Ring C work
- Ring C → next, can be written as pure logic + unit-testable
- Ring D (funnel envelope) → DEFERRED to follow-up
- Ring E (variant explorer) → no longer needed; spike served its purpose
