---
# AlaskaRouter-m3dv
title: 'Try: tighter vertical rhythm (row padding 8 → 6, rail band 17 → 15)'
status: todo
type: task
priority: normal
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T14:08:51Z
parent: AlaskaRouter-e0vm
---

Small per-row reduction (~4pt) adds up to ~32pt of breathing room across an 8-stop trip. Should land after the row chrome lightens so the new density doesn't fight against still-bulky elements. Easy to reject (revert the numbers).



## Reframing (user, Bellevue House moment)
Direct vertical tightening (less .padding(.vertical), shorter rail band) is the wrong move while the distance label sits in its own band between rows — that band is the natural floor between two pips and squeezing it makes the number cramped.

Better future direction (Macdonald villa, Kingston): split the layout horizontally so the distance label rides in a SIDE COLUMN (or a half-step offset between two pips, like Italianate split-floor architecture). That decouples row height from distance-label height; we can then tighten row padding without compromising the label.

Blocked on: deciding distance-label visual size first (user wants to play with it), then designing the side-column placement, then revisiting vertical tightness. Not before.
