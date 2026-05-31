---
# AlaskaRouter-ir85
title: On-map controls + scale shouldn't chase the bottom sheet (anchor them, let sheet cover)
status: completed
type: bug
priority: high
created_at: 2026-05-20T11:29:33Z
updated_at: 2026-05-20T19:23:15Z
parent: AlaskaRouter-xtua
---

The zoom +/-, locate-me, and scale-indicator UI currently dynamically lift themselves up as the bottom sheet expands (collapsed -> overview -> full), via a 'sheetClearance' padding tied to bottomSheetDetent. The intent was to keep them reachable while the sheet is open.

User feedback (verbatim): 'I constantly miss the click and feel like I'm hunting a running cockroach. UI lesson learned — buttons stay still. If I need them I'll just close the sheet (mental model — on-map tools needed when I'm focused on working with map, I'm not in the sheet mode). Choose the best place for those buttons and scale like there is no any sheet out there and leave them. Sheet will just open above and hide them, that's fine.'

## Desired behavior

- Zoom +/- buttons, locate-me, and scale indicator are pinned to a FIXED position relative to the screen (not the sheet)
- Sheet at collapsed detent: tools are visible above the sheet edge
- Sheet at overview / full detent: sheet covers the tools — that's fine, the user closes the sheet when they need them
- No animation chase, no jumping

## Likely implementation

In RootView, the VStack containing MapControls + ScaleIndicator uses '.padding(.bottom, sheetClearance)' where sheetClearance switches on bottomSheetDetent. Replace with a fixed value (likely the .collapsed clearance, ~110pt, which already accounts for the standard collapsed-header height).

Drop sheetClearance as a computed property entirely, or simplify it to a constant.

## Risk

User can no longer access zoom +/- while the sheet is at .full. Acceptable per their explicit mental model: 'on-map tools needed when I'm focused on working with map, I'm not in the sheet mode.'

- [x] Replace sheetClearance switch with a constant
- [x] Re-screenshot at all three detents (collapsed / overview / full) to confirm controls stay put — user-approved on sim screenshots
- [x] Verify scale indicator stays at the same bottom-left position too — user-approved on sim screenshots

## Summary of Changes

`AlaskaRouter/App/RootView.swift`:

- Replaced the `sheetClearance` computed property (which switched on `bottomSheetDetent`) with a single constant `mapControlsBottomClearance = 110` (the previous `.collapsed` value — already clears the collapsed sheet header).
- Removed the `if bottomSheetDetent != .full` guard that hid the on-map controls at full detent. Controls now always render; the sheet expands above them and naturally covers them at `.overview` / `.full`.
- Both `ScaleIndicator` and `MapControls` now use the same fixed `.padding(.bottom, mapControlsBottomClearance)` — no animation chase.

Code comments updated to point at this bean and explain the user's mental model ("on-map tools live in map mode; close the sheet to get to them").

User verification of the on-device behavior is pending — needs a ⌘R from Xcode (CLI build can't auto-register the iPhone with the developer account).
