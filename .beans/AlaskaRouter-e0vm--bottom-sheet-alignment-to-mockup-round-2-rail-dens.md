---
# AlaskaRouter-e0vm
title: 'Bottom-sheet alignment to mockup (round 2): rail, density, buttons, icon sizes'
status: in-progress
type: epic
priority: high
created_at: 2026-05-29T19:35:36Z
updated_at: 2026-05-29T19:35:36Z
---

The bottom sheet has drifted from design/mocks/sheet.jsx and feels crowded/heavy. A second alignment pass (the first, AlaskaRouter-9634, did fonts/blocks/palette). Work through the mock deltas in steps, starting with the timeline rail + per-leg distance.

## Known deltas to align (refine with a full mock audit)
- [ ] Timeline rail connecting stop pips (block-colored top/bottom segments) — MISSING in app — and the per-leg distance placed ON the rail between cells (removes from/to ambiguity). [first task]
- [ ] Pip / numbered-icon sizes (mock pip = 16pt; app = 22pt) and overall icon sizing.
- [ ] Row density / spacing / min-height — reduce the crowded, heavy feel.
- [ ] Buttons & drag handles (mock: left drag-dots + split + remove; app: trash/+); sizes & styles.
- [ ] Block header styling vs mock.

Each becomes its own child task as we get to it.
