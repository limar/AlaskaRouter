---
# AlaskaRouter-8szw
title: Humanized route line — drunk-geologist broken-pencil aesthetic
status: completed
type: feature
priority: normal
created_at: 2026-05-19T07:16:44Z
updated_at: 2026-05-19T18:59:12Z
parent: AlaskaRouter-xtua
---

Named v1 polish requirement. Current LineStyleLayer is a clean Bezier-smoothed polyline. Goal is an analog/warm route line that feels hand-drawn: slight thickness jitter, color drift, possibly subtle paper-grain texture along the path. The 'drunk geologist with a broken pencil' phrasing is the user's locked aesthetic target.



## Summary of Changes

Solved by AlaskaRouter-02pm v11 work. The translucent two-stroke wash + core pattern with zoom-interpolated width gives the route the 'humanized highlighter / pencil over road' aesthetic the original requirement (project_v1_map_polish.md) called for — strong color that doesn't hide the basemap, wider than the road at every zoom, hand-drawn marker feel rather than a CAD line.
