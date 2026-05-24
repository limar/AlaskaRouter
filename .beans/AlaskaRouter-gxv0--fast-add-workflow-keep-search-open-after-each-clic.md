---
# AlaskaRouter-gxv0
title: Fast-add workflow — keep search open after each + click
status: in-progress
type: feature
priority: high
created_at: 2026-05-24T15:58:44Z
updated_at: 2026-05-24T16:01:28Z
parent: AlaskaRouter-ka6b
---

User feedback (2026-05-24):
> When a waypoint added from the search (the only way currently) we focus the map on it (thumbs up) and close & minimize the search bar. I suggest LEAVING the search open. I just change the search term, click "+", change term, click, change-click - the fast add workflow.

## Current behavior (post-wqt4)

\`handleFastAdd\`:
1. \`isSearchFieldFocused = false\` — blurs the field
2. \`barState = .collapsed\` — collapses the search bar to the pill
3. \`searchService.setQuery("")\` — clears the query
4. Pans camera to new waypoint
5. Returns to stops mode in the sheet

So the user has to re-tap the search bar to add another stop. Slow.

## Desired behavior

After "+" tap:
- Keep \`isSearchFieldFocused = true\` (keyboard stays up)
- Keep \`barState = .expanded\` (results list still visible if there's a query)
- Clear \`searchService.setQuery("")\` so user types the next term immediately
- Still pan camera to new waypoint (visual confirmation)
- Still flip sheet mode to .stops (so when user dismisses search, the new waypoints are visible)

## Open question

Sheet visibility while search is active: the existing rule is \`if let trip = activeTrip, !isSearchActive { TripBottomSheet(...) }\` — sheet hides during search. With the new workflow, sheet stays hidden during rapid-add. User sees waypoints on the map (panning to each), and the sheet appears when search is dismissed. Acceptable.

## Checklist

- [ ] Modify handleFastAdd: keep field focused + bar expanded
- [ ] Still pan camera, still flip sheet mode
- [ ] Verify the preview-callout path (handleAddPreviewed) — does the user want the same change there? For now leave handleAddPreviewed unchanged (preview is a different flow — user is intentionally looking at one specific result).
- [ ] On-device verify (pending user check): type, +, type, +, +, +, then tap-outside-search → see all added stops


## Summary of Changes

`handleFastAdd` no longer:
- sets `isSearchFieldFocused = false` (keyboard stays up)
- sets `barState = .collapsed` (search bar stays expanded with the dropdown still rendering)

It still:
- clears the query so the user types the next term immediately (`searchService.setQuery("")`)
- pans the camera to the new waypoint for visual confirmation
- flips `sheetMode = .stops` so when the user eventually dismisses search, the sheet shows the new stops

The preview-callout add path (`handleAddPreviewed`) is unchanged — it's a different intentional "I'm looking at this one specific result" flow and keeps its current collapse-search-on-add behavior.
