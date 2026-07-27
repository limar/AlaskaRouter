---
# AlaskaRouter-a44b
title: '"Open in…" sheet title is clipped by the sheet''s top edge'
status: todo
type: bug
priority: normal
created_at: 2026-07-27T21:33:50Z
updated_at: 2026-07-27T21:36:47Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. In the export-to-maps sheet, the "Open in…" title collides with the sheet's upper border / drag indicator and is partially cut. See the field screenshot.

## Cause — `AlaskaRouter/Sharing/ShareToMapsSheet.swift`
- line 76: `.presentationDetents([.height(220)])` — a hard-coded height. With four apps installed the grid wraps to **two rows** (field screenshot shows exactly this: Apple/Google/Waze on row 1, Maps.me on row 2), so the content overflows 220 pt and the header gets pushed under the top edge.
- line 61: `.padding(.top, 4)` — not enough clearance for `.presentationDragIndicator(.visible)`, which draws inside the sheet's top inset.

## Fix direction
Make the detent height follow the actual row count (or measure the content), and give the header real clearance below the grabber. On the Simulator only Apple Maps is available, so **this bug does not reproduce there** — verify with 2+ rows, i.e. on the device with Google/Waze/Maps.me installed, or by faking `availableApps` behind a launch arg.

## Todo
- [ ] Content-driven detent height (or `.fraction` / measured)
- [ ] Header clearance below the drag indicator
- [ ] Verify at 1, 3 and 4 apps — device screenshot at full res, matching the field failure surface
