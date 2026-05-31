---
# AlaskaRouter-e0vm
title: 'Bottom-sheet alignment to mockup (round 2): rail, density, buttons, icon sizes'
status: todo
type: epic
priority: high
created_at: 2026-05-29T19:35:36Z
updated_at: 2026-05-31T14:20:04Z
---

The bottom sheet has drifted from design/mocks/sheet.jsx and feels crowded/heavy. A second alignment pass (the first, AlaskaRouter-9634, did fonts/blocks/palette). Work through the mock deltas in steps, starting with the timeline rail + per-leg distance.

## Known deltas to align (refine with a full mock audit)
- [ ] Timeline rail connecting stop pips (block-colored top/bottom segments) — MISSING in app — and the per-leg distance placed ON the rail between cells (removes from/to ambiguity). [first task]
- [ ] Pip / numbered-icon sizes (mock pip = 16pt; app = 22pt) and overall icon sizing.
- [ ] Row density / spacing / min-height — reduce the crowded, heavy feel.
- [ ] Buttons & drag handles (mock: left drag-dots + split + remove; app: trash/+); sizes & styles.
- [ ] Block header styling vs mock.

Each becomes its own child task as we get to it.



## Round-2 working principles (added 2026-05-30)
- We are at a working/stable point. Goal of this round: subtle decluttering on top of features that work.
- **TRY framing**: every child below is a TRIAL — implement, evaluate live, accept OR reset. One commit per try so 'git reset --hard <parent>' is the escape hatch.
- **No Great Leap Forward**: 1–3 small tries at a time, focused on one UI surface. The pieces that work today stay working.
- Deferred for now: OFFLINE/Routing pill (no strong need), inline split + retire 'Add separator' row (bigger UX), category glyph next to name (only if rows still feel busy after the other tries).
- All toasts to be dropped (Add toast + Undo toast). The DeletedStopSnapshot model stays so a future undo path (shake, ⌘Z) is still open.
