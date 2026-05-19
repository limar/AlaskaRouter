---
# AlaskaRouter-fuu4
title: 'Selected waypoint icon: keep normal size, fly above ground with shadow'
status: todo
type: feature
priority: normal
created_at: 2026-05-19T19:40:44Z
updated_at: 2026-05-19T19:40:44Z
parent: AlaskaRouter-xtua
---

Change the selected-waypoint visual treatment. Today the selected style is the SAME icon but rendered LARGER (60pt vs 44pt sobresaliente). Replace with same-size icon (44pt) plus a subtle ground shadow offset below+behind, so it looks like the icon has lifted off the map. Reads as 'I'm picked up, look at me' without needing extra size that crowds neighboring labels.

Implementation hint:
- The marker UIImages live in WaypointIcons.swift. Render the selected variant as the same disc/ring/dot at 44pt + a soft ellipse shadow rendered slightly below + an internal Y-offset so the disc appears raised.
- Could use MapLibre's iconOffset to bump the icon up a few pixels and a SEPARATE 'shadow' icon-image rendered first at the original anchor.

Depends on the icon-rendering work already done (AlaskaRouter-amh7 was about icon registration / SHA256 collision — no longer a blocker).
