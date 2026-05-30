---
# AlaskaRouter-sopx
title: 'Try: defer ribbon recompute so reorder drop feels instant'
status: scrapped
type: task
priority: high
created_at: 2026-05-30T11:52:53Z
updated_at: 2026-05-30T12:26:13Z
parent: AlaskaRouter-e0vm
---

Hypothesis: the drop's slow finalize is the routeRibbons recompute running synchronously on the main thread during the same render pass as the SwiftData mutation triggered by the move. TRY a one-line defer of the sync call: DispatchQueue.main.async (or Task { await Task.yield() }) so the drop animation completes first, then the ribbon recompute kicks in a frame later. Trivially reversible.

## Accept criterion
- Dropping a separator feels instant (the row lands without hang).
- Ribbons update within a frame or two — no visible jank.
- No regression to swipe-to-delete, tap-to-collapse, or stop reorder.

## Reasons for Scrapping
The ribbon recompute is not the fat operation — deferring syncTripRouteLayer to next runloop made no perceptible difference. User-observed sequence: drop → row VISIBLY DISAPPEARS → pause → row reappears with original title at *some* position → drop animation runs → title updates at the end. The 'fat' work happens BEFORE the drop animation starts, which rules out the ribbon recompute (that runs as part of the body re-render that follows the .onMove handler returning).
