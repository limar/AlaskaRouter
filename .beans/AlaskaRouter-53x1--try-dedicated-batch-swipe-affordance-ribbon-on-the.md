---
# AlaskaRouter-53x1
title: 'TRY (dedicated batch): swipe-affordance ribbon on the trailing edge of stop rows'
status: todo
type: task
priority: normal
created_at: 2026-05-30T09:18:23Z
updated_at: 2026-05-30T10:23:44Z
parent: AlaskaRouter-e0vm
---

Once the trash button is gone (AlaskaRouter-24t5), the trailing edge loses its visual counterweight and there is no hint that swiping reveals a Delete action. TRY a thin vertical ribbon on the trailing edge of each stop row as a discoverability cue. Variants to compare on-device:

- Neutral grey ribbon — minimal, 'there is something here'
- Blue/accent ribbon — suggests 'actions here'
- Red/destructive ribbon — preview of the delete colour beneath

Play with width (1.5–3pt), height (full row vs centered band), opacity. Decide via live A/B. The intent is to keep rows light while still hinting at the swipe — not to bring the trash back.



## Reframed (after batch 2 ship + accessibility note from user)

User raised an important point: swipe-only is a power-user gesture. Many users — motor-impairment, trackpad/mouse, simulator, Apple TV remote-cursor — struggle with swipe. Apple themselves keep BOTH gesture and a tappable affordance in Mail / Notes / Reminders precisely for this. A pure 'swipe-affordance ribbon' solves discoverability without solving accessibility.

**Upgrade the trajectory**: bring back a small `-` button on the trailing edge, but make it 'simulate the swipe' visually — tap `-` → row offsets left under animation → reveals a trailing red Delete → tap Delete confirms, tap elsewhere on the row cancels. Same UX/mental model as the system swipe, but tappable and accessibility-friendly. The POSH UI pattern the user remembers from another app.

Implementation note: the literal 'programmatically open .swipeActions' API doesn't exist in SwiftUI. We custom-roll the reveal — the row's content gets a horizontal offset, a trailing red Delete view fades in, the gesture system tracks tap-outside-to-cancel. Two states per row (idle / armed) tracked locally. Coexists with the system `.swipeActions` (or we drop `.swipeActions` entirely and use only our pattern — TBD when we get there).

Original 'swipe-affordance ribbon' idea (thin colored bar on the trailing edge) becomes a fallback option if the `-` route turns out too hairy.
