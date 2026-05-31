---
# AlaskaRouter-6360
title: Git-LFS for large binary assets (alaska-pack.pmtiles ~447MB)
status: scrapped
type: task
priority: normal
created_at: 2026-05-19T07:17:29Z
updated_at: 2026-05-20T10:23:50Z
parent: AlaskaRouter-xtua
---

alaska-pack.pmtiles is 447MB and committed directly. Exceeds GitHub's 100MB single-file push limit and bloats clones. Set up git-lfs tracking before any push to GitHub (personal repo or OSS). Alternative: host the pack in iCloud Drive (already the v2 distribution plan) and have the app fetch on first launch — but for v1 personal use, the in-bundle path needs LFS.



## Reasons for Scrapping

Superseded by AlaskaRouter-76y3 which picked a GitHub Releases + regenerate-script hybrid over Git-LFS. Reasoning:

- Git-LFS storage and bandwidth are ongoing costs (~$5/mo minimum past the 1 GB free tier; 50 MB free bandwidth burns in roughly one fresh clone)
- pmtiles is derived data — regenerable via tools/build-pack/download_tiles.py — so versioned-in-git semantics aren't earned
- GitHub Releases give us free versioned binary attachments tied to data/* tags; perfectly fits 'binary build artifact' status
- Hybrid scales: each future region pack (Yukon, BC, etc.) is just another release asset
