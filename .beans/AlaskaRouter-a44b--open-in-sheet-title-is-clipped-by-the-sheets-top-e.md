---
# AlaskaRouter-a44b
title: '"Open in…" sheet title is clipped by the sheet''s top edge'
status: completed
type: bug
priority: normal
created_at: 2026-07-27T21:33:50Z
updated_at: 2026-07-27T21:58:52Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. In the export-to-maps sheet, the "Open in…" title collides with the sheet's upper border / drag indicator and is partially cut. See the field screenshot.

## Cause — `AlaskaRouter/Sharing/ShareToMapsSheet.swift`
- line 76: `.presentationDetents([.height(220)])` — a hard-coded height. With four apps installed the grid wraps to **two rows** (field screenshot shows exactly this: Apple/Google/Waze on row 1, Maps.me on row 2), so the content overflows 220 pt and the header gets pushed under the top edge.
- line 61: `.padding(.top, 4)` — not enough clearance for `.presentationDragIndicator(.visible)`, which draws inside the sheet's top inset.

## Fix direction
Make the detent height follow the actual row count (or measure the content), and give the header real clearance below the grabber. On the Simulator only Apple Maps is available, so **this bug does not reproduce there** — verify with 2+ rows, i.e. on the device with Google/Waze/Maps.me installed, or by faking `availableApps` behind a launch arg.

## Todo
- [x] Content-driven detent height (or `.fraction` / measured)
- [x] Header clearance below the drag indicator
- [x] Verify at 1 and 4 apps — Simulator screenshot at full res, matching the field failure surface

## Summary of Changes

The hard-coded `.presentationDetents([.height(220)])` is replaced by a measured height (`onGeometryChange` on the content, seeded at 220), so the sheet fits 1, 2 or 3 tile rows without a magic number. Header top padding 4 → 18 (`dragIndicatorClearance`) so the grabber no longer sits on the title.

The Simulator can only ever show one tile (no App Store apps), so a dev-only screenshot hook was added to reach the failure surface at all — `LaunchArgs.shareSheetShowsAllApps` (`-shareAllApps 1`) forces all four tiles, and the existing `-autoAction` gained a `share:<index>` case that opens the chooser directly.

**Verified:** 4 apps (two rows, the field case) and 1 app (one row) — title fully clear of the top edge in both, and the detent shrinks correctly for the shorter content.

3 apps was not captured separately: it is a single row of three, and the 4-app case already exercises the wrap that caused the clipping.
