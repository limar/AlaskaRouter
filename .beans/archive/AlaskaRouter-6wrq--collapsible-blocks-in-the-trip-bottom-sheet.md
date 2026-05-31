---
# AlaskaRouter-6wrq
title: Collapsible blocks in the trip bottom sheet
status: completed
type: feature
priority: high
created_at: 2026-05-29T17:56:37Z
updated_at: 2026-05-29T18:37:20Z
---

Long itineraries require heavy scrolling. Let the user collapse/expand each block (day/stretch) in the bottom-sheet stops list. Chosen via spike AlaskaRouter-xq6w: Option 1 (flat List + custom chevron + filter), NOT native Section(isExpanded:).

## Design (agreed with user)
- Each block header gets a disclosure chevron (down=open, right=collapsed); tap the header to toggle, animated.
- Collapsed block hides its stop rows; the "N stops" subline is the summary.
- Collapsed block headers are NOT draggable — hide the hamburger handle and .moveDisabled them (no moving collapsed sections). Expanded headers keep current behavior.
- Dragging a stop near a collapsed block: Option (a) — it lands before/after the collapsed block, which stays collapsed. This is the natural .onMove behavior (no hover-to-expand, which .onMove can't do).
- Reorder/delete handlers map VISIBLE (filtered) offsets back to full trip.listItems indices.
- Collapse state ephemeral (per session) for v1.

## Tasks
- [x] Implement collapse state + visibleEntries() filter + chevron header + tap toggle + handle hiding
- [x] Map visible→full indices in reorderListItems / deleteListItems
- [x] Build (BUILD SUCCEEDED)\n- [x] Verify on simulator — confirmed by user ("works very good").

## Open follow-ups (not in scope unless asked)
- Whether to also disable dragging EXPANDED section headers (user implied section reordering isn't a real use case).
- Auto-expand a block when a stop is added into it (avoid "added but hidden").
- Persist collapse state per trip.

## Summary of Changes
Bottom-sheet block headers are now collapsible (TripBottomSheet): a chevron toggles each block, collapsed blocks hide their stops (with animation) and lock dragging (handle hidden + .moveDisabled). reorderListItems/deleteListItems map the visible (collapse-filtered) offsets back to full trip.listItems indices; with nothing collapsed the path is identical to before. Spike (CollapseSpike target + spikes/D_collapse) used to choose Option 1 was removed.
