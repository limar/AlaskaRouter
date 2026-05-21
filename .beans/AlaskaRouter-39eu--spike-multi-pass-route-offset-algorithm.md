---
# AlaskaRouter-39eu
title: 'Spike: multi-pass route offset algorithm'
status: todo
type: task
priority: high
created_at: 2026-05-21T05:02:01Z
updated_at: 2026-05-21T05:02:44Z
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
