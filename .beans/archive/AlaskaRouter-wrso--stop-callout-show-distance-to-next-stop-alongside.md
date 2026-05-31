---
# AlaskaRouter-wrso
title: 'Stop callout: show distance to next stop alongside from previous'
status: completed
type: feature
priority: normal
created_at: 2026-05-30T06:54:37Z
updated_at: 2026-05-30T07:56:16Z
---

Per user request: the existing 'X km from previous' in StopCallout feels informative; the callout has plenty of space, so add a parallel 'X km to next' line. Nil for the last stop (no next). Same straight-line haversine + DistanceFormat path as the from-previous helper, so it honors the km/mi unit toggle.

## Tasks
- [x] Add distanceToNextText param to StopCallout, render under detailLine
- [x] RootView: distanceToNextText(idx:in:) helper + pass at instantiation
- [x] Build + self-screenshot to confirm both lines render
- [x] User visual verify + commit — user approved through iterations: split lines, distance-source fix, named neighbors.

## Layout v2 + distance-source fix
Layout: split the combined 'category · from previous' into three lines so the distance pair reads as a group (Option 1 per user).
Bug: the callout was using straight-line haversine while the bottom sheet uses road distance via the snapped polyline, so the two showed different numbers for the same leg. Both surfaces now share Trip.legDistancesMeters (with straight-line fallback). Verified on the Finger Mountain callout: 67 km from previous + 124 km to next match the bottom sheet's rail labels exactly.

## Final polish — named neighbors
Replaced the literal 'from previous' / 'to next' wording with the actual previous/next stop labels, e.g. '67 km from Yukon River Camp', '124 km to Arctic Interagency Visitors Center'. Long names truncate with the system ellipsis (lineLimit 1, user-accepted). Nil labels fall back to 'previous'/'next' so the old wording survives for unnamed waypoints.

## Summary of Changes
Added a 'to next' distance to StopCallout alongside the existing 'from previous'. Refactored the detail block into three short lines (category / from / to) so the distance pair reads as a visual group (Option 1 per user). Fixed a parity bug: callout was straight-line haversine, bottom sheet was road via the snapped polyline → both now share Trip.legDistancesMeters (with straight-line fallback). Both lines name the actual neighbor stop instead of a literal 'previous'/'next'.
