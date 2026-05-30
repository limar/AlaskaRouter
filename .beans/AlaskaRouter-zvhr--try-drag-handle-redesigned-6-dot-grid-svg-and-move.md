---
# AlaskaRouter-zvhr
title: 'Try: drag handle redesigned (6-dot grid SVG) and moved to the LEADING edge'
status: todo
type: task
priority: high
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T09:08:35Z
parent: AlaskaRouter-e0vm
---

Mock has a 6-dot grid (two cols × three rows of small circles, ~32% alpha) on the LEFT of each row instead of line.3.horizontal on the right. Balances the row, lighter visual weight, more distinctive. TRY:
- Recreate the 6-dot glyph in SwiftUI (small Canvas or HStack of two VStacks of Circles).
- Move it to the leading edge of stop rows (and probably block headers when they're draggable too, but that's a sub-decision).
- Block-0 synthetic header still hides it.
- Collapsed blocks still hide it (jhw8 rule).

Accept criterion: trailing edge no longer needs a drag affordance; leading edge has the dots; reorder still works.
