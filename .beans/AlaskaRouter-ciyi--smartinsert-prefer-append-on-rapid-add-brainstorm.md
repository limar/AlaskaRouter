---
# AlaskaRouter-ciyi
title: 'SmartInsert: prefer append on rapid-add; brainstorm fix for star-trip detours'
status: in-progress
type: bug
priority: critical
created_at: 2026-05-31T14:43:01Z
updated_at: 2026-05-31T15:12:47Z
parent: AlaskaRouter-xtua
---

Adding stops one-by-one via fast-add can produce a stop order that doesn't match how humans plan a trip ("in the sequence I pass them"). User-reported symptoms:

- "I add a stop, it becomes N1. I add another, it becomes N1 too, shifting the previous to N2." — i.e., new stops shoulder existing ones aside.
- The "star" trip (drive out → return → drive out in a different direction) is mis-handled: the next outbound point may sit closest to the hub and get inserted at the hub's slot, breaking the planned ordering.

## Current behavior

[SmartInsert.swift](AlaskaRouter/Data/SmartInsert.swift) uses classic cheapest-edge TSP insertion: for trips with ≥ 2 stops, picks the n+1 position minimising haversine detour. For 0- or 1-stop trips it appends. Called from `handleFastAdd` and `handleAddPreviewed` in [RootView.swift](AlaskaRouter/App/RootView.swift).

The algorithm is mathematically right for linear out-and-back routes but wrong for human planning intent, because it minimises GEOMETRY not user INTENT. The user's mental model is sequential ("stops in the order I'll pass them"), not least-detour.

## Star-trip pathology (concrete example)

Hub at Anchorage. Trip = [Anchorage, Seward, Anchorage]. User now wants to add Talkeetna (north of Anchorage) as the next leg. Cheapest insertion will likely place Talkeetna between Anchorage and Seward (a small mid-route detour), instead of appending it after the second Anchorage stop as the user clearly intends.

There is no purely-geometric heuristic that distinguishes "next destination on the user's plan" from "least-detour insertion point" — the information needed is the user's intent, which is not in the coordinates.

## Brainstorm — options

1. **Append by default.** Simplest, matches the planning mental model. Removes magic, easy to predict. Drawback: when user genuinely adds a mid-route stop, they have to reorder manually (already supported via bottom-sheet drag-to-reorder).

2. **Append + post-add nudge.** Append, but if cheapest-edge would have placed it elsewhere with significant savings (>X km), show a toast: "Insert between Stop 3 and Stop 4 instead? — saves 40 km — Undo". Powerful but breaks the user's flow.

3. **Smart-add toggle.** Per-trip or global toggle: "Insert at best position" vs "Append to end". Default = append. Power-users get the old behavior for big criss-cross routes.

4. **Insertion-time chooser, only when ambiguous.** Compute the best 2–3 candidate positions; if they're close in cost, prompt; if append clearly wins, append. Risk: cognitive interruption during rapid-add.

5. **Heuristic: prefer the back half of the route.** When candidate-position is within K stops of the END and the cost difference is small, prefer the later position. Reduces "inserted near the start" surprises without abandoning the smart logic entirely. Hand-tuned threshold; may still surprise.

6. **Heuristic: prefer append unless detour penalty for appending is very large.** Append unless `cost(n) > cost(best) + threshold`. Aligns with "user is adding stops as they go" assumption.

## Decision (2026-05-31, user)

Option #4 from the brainstorm: keep SmartInsert, only change the rapid-add (`+` button) path to always append. Preview-add (`handleAddPreviewed`) keeps SmartInsert because it's a deliberate "I'm looking at this one specific result" flow where the cheapest-edge insertion makes sense.

Rationale: the rapid-add workflow is the one where users build a trip in the order they intend to drive it; preview-add is more curated. Two paths, two policies.

## Checklist

- [x] Get user sign-off on the brainstorm direction
- [x] Added `SmartInsert.appendOnly(coordinate:label:category:into:using:)` in [SmartInsert.swift](AlaskaRouter/Data/SmartInsert.swift) — sibling to `insertSmart`, always uses `trip.orderedWaypoints.count`
- [x] Switched `handleFastAdd` in [RootView.swift](AlaskaRouter/App/RootView.swift) to call `SmartInsert.appendOnly`
- [x] Left `handleAddPreviewed` on `SmartInsert.insertSmart` — preview-add still does cheapest-edge
- [x] Added `testAppendOnlyAlwaysGoesToTheEndEvenWhenGeometryWouldPreferElsewhere` in [Tests/DataInvariantTests.swift](Tests/DataInvariantTests.swift) — passes
- [ ] On-device verify the rapid-add flow: A → B → C anywhere → trip = [A, B, C]

## Summary of Changes

For the rapid-add flow (`+` button on search rows), waypoint insertion is now strictly append-only — the new stop always lands at `trip.orderedWaypoints.count`, matching how users mentally list stops when typing them in driving order. The cheapest-edge geometric insertion stays in place for the preview-add flow (where the user has stopped to consider one specific result and the optimisation makes sense).

Files touched:
- [AlaskaRouter/Data/SmartInsert.swift](AlaskaRouter/Data/SmartInsert.swift) — new `appendOnly(...)` static, sibling to `insertSmart(...)`.
- [AlaskaRouter/App/RootView.swift](AlaskaRouter/App/RootView.swift) — `handleFastAdd` switched from `insertSmart` to `appendOnly`. `handleAddPreviewed` unchanged.
- [Tests/DataInvariantTests.swift](Tests/DataInvariantTests.swift) — new test `testAppendOnlyAlwaysGoesToTheEndEvenWhenGeometryWouldPreferElsewhere` asserts that even when a candidate is geometrically between two existing stops, `appendOnly` still puts it at the end.
