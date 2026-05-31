---
# AlaskaRouter-zvhr
title: 'Try: drag handle redesigned (6-dot grid SVG) and moved to the LEADING edge'
status: completed
type: task
priority: high
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T10:23:02Z
parent: AlaskaRouter-e0vm
---

Mock has a 6-dot grid (two cols × three rows of small circles, ~32% alpha) on the LEFT of each row instead of line.3.horizontal on the right. Balances the row, lighter visual weight, more distinctive. TRY:
- Recreate the 6-dot glyph in SwiftUI (small Canvas or HStack of two VStacks of Circles).
- Move it to the leading edge of stop rows (and probably block headers when they're draggable too, but that's a sub-decision).
- Block-0 synthetic header still hides it.
- Collapsed blocks still hide it (jhw8 rule).

Accept criterion: trailing edge no longer needs a drag affordance; leading edge has the dots; reorder still works.

## Summary
Drag handle redesigned as a 6-dot grid (2 cols × 3 rows of small filled circles) and moved from the trailing edge to the LEADING edge of stop rows — mock-aligned, lighter weight than line.3.horizontal, and the new column visibly indents stops under their block headers. Same dragColWidth (14pt) reserved on the incoming-leg band so the rail's x-position stays continuous between band and pip.

First-cut dot styling (mock-faithful 32% textMuted at 2pt) was invisible over our translucent sheet + bright map. Bumped to 45% textStrong at 2.5pt for readability — same dissolves-on-translucency root cause tracked in AlaskaRouter-1ag5. Pip/dot SIZE alignment intentionally left for the AlaskaRouter-3lr9 batch (pip shrink) — they should scale together to keep proportional.
