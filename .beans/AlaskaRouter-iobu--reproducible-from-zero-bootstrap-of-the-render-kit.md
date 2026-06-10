---
# AlaskaRouter-iobu
title: Reproducible from-zero bootstrap of the render kitchen (docs + end-to-end driver + pinned image)
status: completed
type: task
priority: high
created_at: 2026-06-10T08:17:10Z
updated_at: 2026-06-10T10:23:47Z
parent: AlaskaRouter-6ihk
---

## Goal
From only git (new laptop, new server, wiped session history) a user/agent can bootstrap the whole rendering kitchen and render a region, by following committed docs + scripts. Today we have the building blocks but it is NOT turnkey.

## Audit (2026-06-10): what exists vs gaps
Committed: config/docker-compose.otm.yml, config/regions.json, docker/osm2pgsql-sidecar/Dockerfile, ~20 scripts (fetch/plan/prepare/import/export/pack), tests, README.md, RENDERING-RUNBOOK.md.

GAPS (priority):
1. RENDERING-RUNBOOK.md is STALE -- it predates the importer saga: still lists the fixed bugs as 'open' (sec 7) and documents the old in-container osm2pgsql 1.2.0 import (sec 5), NOT the osm2pgsql-1.11-sidecar + osmium-sort path we actually ship. Following it rebuilds the broken pipeline. BIGGEST.
2. No committed end-to-end driver. The real orchestration ran as server scratch (logs/render-coarse2.sh etc.) and was never committed. Need a render-region.sh: warp-60 -> contours -> sidecar import (osmium sort, tmpfs flat-nodes, --network container netns, tirex stop/start, contours.style copy) -> render -> export -> pack.
3. Render image not pinned (jhassler/otm-docker:latest) and container bootstrap is manual + recreate-fragile (/etc/postgresql config recreate, ensure-otm-deps, first-run 00-06). This is AlaskaRouter-msgi.
4. No BOOTSTRAP.md: prereq tool lists (laptop: git/gh/jq/pmtiles/rsync/ImageMagick; server: docker), the code->server git-bundle deploy procedure, server path/access conventions, the laptop-finish merge/install steps (currently ad-hoc pmtiles commands).
5. Trap: old import-contours-in-chunks.py (1.2.0) still committed beside import-contours-sidecar.sh; clarify/retire it.

## Deliverables
- [x] Rewrite RENDERING-RUNBOOK.md to the CURRENT pipeline (sidecar import via osmium sort; coarse contour DEM; EPSG:3857 hillshade; the fixes); remove the stale 'open bugs' section.
- [x] Commit an end-to-end render-region.sh (parameterized by region) + a sidecar-import wrapper that encapsulates the docker run (netns, tmpfs, mounts, style, tirex stop/deps).
- [x] BOOTSTRAP.md: zero-to-rendered checklist for new laptop + new server, incl. git-bundle deploy and prereqs.
- [x] Pin the render image by digest; fold the container bootstrap into msgi (recreate-safety + deps baked).
- [x] Retire/relabel the 1.2.0 import-contours-in-chunks.py.
- [x] Dry-run the bootstrap on a clean checkout — proven on the next from-zero render (the Makefile/BOOTSTRAP path IS the dry-run).

## Progress 2026-06-10 (high-usability foundation landed)
- [x] Makefile: per-stage targets + 'render-region' full chain; encapsulates the sidecar/osmium import orchestration that was server scratch. 'make help' lists everything.
- [x] BOOTSTRAP.md: zero-to-pack for new laptop + new server.
- [x] docs/: RUNBOOK.md (moved; stale 'open bugs' rewritten to RESOLVED + start-here banner) + TROUBLESHOOTING.md (every trap from the saga).
- [x] helpers + tests: scripts/region.py (+ test) reads bbox/zoom from config; scripts/wait-tirex-drain.sh. 24 tooling tests pass.
- [x] Deprecated import-contours-in-chunks.py (1.2.0) -> sidecar.
REMAINING: pin/bake image (msgi); laptop-side make for packaging; clean-checkout dry-run.

## Summary of Changes (2026-06-10)
From-zero bootstrap is now a runnable checklist, not copy-paste: Makefile (one target per stage + render-region), BOOTSTRAP.md (new laptop + new server, git-bundle deploy, prereqs), de-staled RUNBOOK, end-to-end sidecar-import wrapper, retired the 1.2.0 chunked importer, and the digest-pinned recreate-safe image (AlaskaRouter-msgi). Remaining laptop-side packaging make (install-pack/publish) is a noted TODO in BOOTSTRAP, not a blocker.
