---
# AlaskaRouter-4r06
title: 'Step A toward 53x1: neutral minus button on stop rows'
status: completed
type: task
priority: high
created_at: 2026-05-30T14:13:09Z
updated_at: 2026-05-30T14:24:49Z
parent: AlaskaRouter-e0vm
---

First half of AlaskaRouter-53x1 (POSH minus-button direction). Smallest try: minus.circle on the trailing edge of each stop row, tap = deleteWaypoint(wp) immediately. No swipe-reveal animation yet. Apple swipe-to-delete remains as the alternative path. DeletedStopSnapshot stays alive in the model for a future undo channel. Step B (swipe-reveal animation, tracked by 53x1) only if A feels too easy-to-misclick.

## Summary
minus.circle outline (17pt, secondary tint) on the trailing edge of each stop row, tap = immediate deleteWaypoint(wp). Apple swipe-to-delete remains as alternative path; DeletedStopSnapshot stays alive in the model for a future undo channel. Right side has visible weight back without shouting.
