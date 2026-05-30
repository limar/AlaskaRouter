---
# AlaskaRouter-io69
title: 'Bug: reorder drop has visible disappear→pause→reappear (SwiftUI internal, not our code path)'
status: todo
type: bug
priority: normal
created_at: 2026-05-30T13:44:05Z
updated_at: 2026-05-30T18:06:52Z
parent: AlaskaRouter-e0vm
---

User-spotted regression: dropping a moved stop or separator visibly disappears for 200+ms, then reappears at some position, *then* animates to the final position with a freshly-updated title. Reads as fade/identity-change instead of clean slide.

## What we measured (NSLog timings, no debugger)
The .onMove handler is essentially free:
- Separator drop: setup=1.5ms loop=0.1ms prune=0.5ms total-sync=2.2ms
- Stop drop:      setup=0.4ms loop=0.2ms prune=0.1ms total-sync=0.7ms

The runloop comes back to our deferred block within ~8ms after the handler returns (DispatchQueue.main.async timing). So nothing in our code path is the fat thing:
- Not the mutation loop
- Not pruneDegenerateSeparators
- Not modelContext.save() (we deferred it; gap before it ran was still 8ms)
- Not body re-renders (those would block the runloop too)

The 200+ms 'pause' is inside SwiftUI's own List drop-animation transition.

## Approaches tried + outcomes
- AlaskaRouter-x5ss — swap Button wrap for .simultaneousGesture(TapGesture) on blockHeaderRow. No effect. SCRAPPED.
- AlaskaRouter-sopx — defer syncTripRouteLayer (ribbon recompute) to next runloop via DispatchQueue.main.async. No effect (ribbons render *after* the drop animation anyway). SCRAPPED.
- Defer modelContext.save() inside reorderListItems. Was already part of x5ss/sopx exploration; no effect.
- Ablation: remove the Color.clear stop-indent placeholder in waypointRow + matching band placeholder. Tested — no effect on animation (left in commit history reverted).

## Suspect (not confirmed, not investigated further)
View-identity drift during the .onMove, plausibly induced by the conditional Group { if synthetic || collapsed { Color.clear } else { dragDots } } inside blockHeaderRow (from exf0), or by the recent dot-column / placeholder structure in waypointRow. Animation-Hitches Instruments would tell us — deferred (further investigation would block development).

## Decision
Deferred. The bug exists but does not block usability — the drop completes, the data is correct, the title updates. Revisit when:
- A clearer hypothesis arises (e.g. matches a known SwiftUI issue)
- We have an Instruments session available
- Or we naturally restructure the row view tree as part of another refinement

## Where we stopped
File state at 08ac804 (exf0 — separator mobility + dot column). All diagnostics + ablation reverted. Cooperation with user worked well; learned NSLog → unified-log streaming via xcrun simctl spawn booted log stream as a debugger-free console technique.



## New evidence (user, 2026-05-30 evening)
User reproduced from scratch after data loss: they built a fresh trip incrementally and noticed the flicker DID NOT happen on the short-leg version of the trip. When they added the final 817 km Deadhorse → North Pole leg (significantly extending the snapped polyline), the disappear-pause-reappear came back.

This is consistent with the heavy-recompute hypothesis (Trip.routeRibbons cost scales with polyline length — cell registration, lane assignment, dilated neighborhood reads all run per-edge). Even though sopx deferred syncTripRouteLayer and it didn't help, that defer only moves the recompute to the next runloop pass — the cost still lands on the main thread, just one frame later. The body re-render that follows the .onMove handler still triggers a synchronous trip.blocks/listItems pass on the new data, and the ribbon recompute lands shortly after.

So io69 is real, polyline-length-driven, and reproducible. Concrete next investigation when revisited: profile routeRibbons under a long polyline + a separator move and see whether the cell registration / lane-assignment phase is the dominant cost. Possible mitigations:
- Cache leg geometry (signatures, cells, lanes) by snapped-polyline identity; only recompute the per-leg COLORS on a separator move.
- Move the heavy computation to a background queue and update MLN layers on main.
- Reduce dilated neighborhood lookups (3×3 → 1×1) for trips with very long polylines.



## Another attempt (2026-05-30 night) — also didn't help
Wrapped reorderListItems's entire body (the move + the SwiftData mutation loop + prune + save) in withTransaction(Transaction(disablesAnimations: true)) on the hypothesis that SwiftData property cascades (wp.order, sep.afterWaypointID, then trip.blocks / trip.listItems / per-block displayName recomputations) were getting pulled into SwiftUI's move-animation transaction and causing the row's visual transition to fade/identity-change instead of slide. **No perceptible difference** — same disappear-pause-reappear pattern. Reverted.

Decision: stop guessing. Profiling with Instruments (Animation Hitches or Time Profiler) is the next legitimate step; further hypothesis-bash is wasting time. Deferred until the user (or future maintainer) has appetite for an Instruments session.
