---
# AlaskaRouter-qy0f
title: Drive-time estimates (persist OSRM duration; per-leg time)
status: todo
type: feature
priority: normal
created_at: 2026-05-29T18:55:02Z
updated_at: 2026-05-29T18:55:02Z
blocked_by:
    - AlaskaRouter-ssl1
---

Deferred from the lengths feature (AlaskaRouter-ssl1). The snap cache stores only coordinates; OSRM's total duration is fetched but discarded and per-leg legs/annotations aren't requested. To show drive time: persist total duration with the snap (show trip total time), and either estimate per-leg time by apportioning the total over leg distances (uniform speed, simplest) or request OSRM legs/annotations for real per-leg durations (routing-layer + cache-schema change). Decide approach when picked up.
