---
# AlaskaRouter-53x1
title: 'TRY (dedicated batch): swipe-affordance ribbon on the trailing edge of stop rows'
status: todo
type: task
priority: normal
created_at: 2026-05-30T09:18:23Z
updated_at: 2026-05-30T09:18:23Z
parent: AlaskaRouter-e0vm
---

Once the trash button is gone (AlaskaRouter-24t5), the trailing edge loses its visual counterweight and there is no hint that swiping reveals a Delete action. TRY a thin vertical ribbon on the trailing edge of each stop row as a discoverability cue. Variants to compare on-device:

- Neutral grey ribbon — minimal, 'there is something here'
- Blue/accent ribbon — suggests 'actions here'
- Red/destructive ribbon — preview of the delete colour beneath

Play with width (1.5–3pt), height (full row vs centered band), opacity. Decide via live A/B. The intent is to keep rows light while still hinting at the swipe — not to bring the trash back.
