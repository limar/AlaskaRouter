---
# AlaskaRouter-36of
title: v1.1 — Field Fixes (post-Alaska)
status: in-progress
type: milestone
priority: high
created_at: 2026-07-27T21:36:47Z
updated_at: 2026-07-27T21:36:47Z
---

The usability round from the first real field test — the Alaska expedition, June–July 2026. Six concrete defects the trip surfaced, all of them things that only show up when you are actually holding the phone on the Dalton Highway rather than driving the Simulator.

Ships as **v1.1.0**, on top of the v1.0.0 tag (commit 3288dc1, the build that was carried).

Social export ("Look What I Did", AlaskaRouter-ctco) came out of the same trip but is deliberately **not** in this milestone: it is a new feature with an open design surface and a real technical unknown, and it shouldn't hold the six fixes.

## Scope
- AlaskaRouter-dd2u — dropped pins on long press only
- AlaskaRouter-rvzg — Google Maps export lands on the wrong place
- AlaskaRouter-o962 — scale ignores the miles tweak + broken imperial ladder
- AlaskaRouter-xogw — scale label not live during pinch
- AlaskaRouter-pmnd — callout "Remove" too loud / wrong slot
- AlaskaRouter-a44b — "Open in…" sheet title clipped

## Working order
1. **No design surface** — o962, a44b, xogw. Straight to code + screenshot proof.
2. **Behaviour, small design** — dd2u (agree the gesture table first), rvzg (needs an on-device URL bake-off; Simulator can't judge it).
3. **Design-led** — pmnd (rendered variants over the real map before any code).
