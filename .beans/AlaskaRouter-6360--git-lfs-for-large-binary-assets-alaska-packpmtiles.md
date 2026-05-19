---
# AlaskaRouter-6360
title: Git-LFS for large binary assets (alaska-pack.pmtiles ~447MB)
status: todo
type: task
priority: normal
created_at: 2026-05-19T07:17:29Z
updated_at: 2026-05-19T07:17:29Z
parent: AlaskaRouter-xtua
---

alaska-pack.pmtiles is 447MB and committed directly. Exceeds GitHub's 100MB single-file push limit and bloats clones. Set up git-lfs tracking before any push to GitHub (personal repo or OSS). Alternative: host the pack in iCloud Drive (already the v2 distribution plan) and have the app fetch on first launch — but for v1 personal use, the in-bundle path needs LFS.
