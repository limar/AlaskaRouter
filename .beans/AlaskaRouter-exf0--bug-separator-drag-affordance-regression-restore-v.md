---
# AlaskaRouter-exf0
title: 'Bug: separator drag affordance regression (restore via leading dot column)'
status: completed
type: bug
priority: high
created_at: 2026-05-30T10:54:52Z
updated_at: 2026-05-30T11:22:32Z
parent: AlaskaRouter-e0vm
---

Regression from AlaskaRouter-tsvw. The user wants to be able to slide a separator up or down between waypoints — e.g., 'sleep overnight after stop X' moves the separator to anchor there. The previous "no real use case" call conflated separator-reordering (legit) with block-reordering (nonsense — road stretches don't swap). The existing .onMove → reorderListItems flow already handles separator-anchor mutation correctly when a header moves in the list; we just dropped the drag affordance with tsvw.

## Fix
- Add a leading 6-dot drag handle to block headers — same dragColWidth (12pt) as stops, in the same fixed column so the leading edge of every row is a single grip rail.
- Headers' content (chip + name) starts immediately after the dot column; stops' content (rail + pip) carries the existing rail-width indent past the dots → variant 2 from the user's ASCII (left-column-aligned dots, indent comes from content, not from dot placement).
- Collapsed headers: hide the dots (invisible spacer of dragColWidth) so no false promise of drag. Trailing chevron.right already signals collapsed.
- Block-0 synthetic header: invisible spacer too (no separator to reorder).
- .moveDisabled(isSynthetic || isCollapsed) so non-synthetic expanded headers are draggable again.
- blockHeaderRow padding: .padding(.horizontal, 12) → .padding(.leading, 14) + .padding(.trailing, 14) so leading edge aligns with the stop rows' dot column.

## Summary
Restored separator mobility (was lost in tsvw). Added the 6-dot grip to non-synthetic, non-collapsed block headers; synthetic block 0 and collapsed headers reserve the column with an invisible spacer so the leading edge is a single grip rail down the whole list. Block-header padding changed from .padding(.horizontal, 12) to .padding(.leading, 14) + .padding(.trailing, 14) so it aligns with stop rows. .moveDisabled(true) → .moveDisabled(isSynthetic || isCollapsed).

Then tuned the stop indentation: stopIndentExtra started at 16 (too wide — pip sat 16pt past the chip's right edge) and was reduced to 0; the HStack's natural 10pt spacing on each side of the placeholder still carries the indent, landing the stop's rail center on the section chip's right edge. Reads as: dot column → chip immediately, or dot column → indent → pip. Section/stop hierarchy clearly visible, no wasted space.
