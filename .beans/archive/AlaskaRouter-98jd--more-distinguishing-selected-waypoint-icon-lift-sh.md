---
# AlaskaRouter-98jd
title: More distinguishing Selected waypoint icon (lift, shadow, glow)
status: scrapped
type: feature
priority: normal
created_at: 2026-05-19T09:26:02Z
updated_at: 2026-05-21T15:17:38Z
parent: AlaskaRouter-xtua
---

Today the selected waypoint icon is just a slightly bigger version of the default (60pt vs 44pt, same palette). When viewed in isolation — no other markers in frame for size comparison — it's easy to confuse with a zoom-in or with the default marker itself.

Make selection unmistakable on its own. Ideas to mix-and-match:
- Heavier drop shadow so the marker appears to lift off the surface
- Subtle glow / colored halo ring extending outward
- Slight vertical offset ("pin lifted off the ground")
- Animated breathing/pulse (gentle, low-frequency)
- Distinct color treatment (e.g. accent color tint, not just bolder ring)

Hard constraint: must remain readable on the warm OpenTopoMap palette and not clash with the route line color. Also keep glyph dependency to Noto Sans Regular only (see AlaskaRouter-ymw6 — bundle other fonts task — for why).

- [ ] Sketch 2-3 visual variants (inline screenshots), pick one with user
- [ ] Implement chosen treatment in WaypointIcons.committedSelected
- [ ] Verify at zoom 8.5 and zoom 11 against the default markers
