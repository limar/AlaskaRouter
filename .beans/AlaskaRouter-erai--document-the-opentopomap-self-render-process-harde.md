---
# AlaskaRouter-erai
title: Document the OpenTopoMap self-render process + harden the workflow
status: in-progress
type: task
priority: high
created_at: 2026-06-04T14:51:34Z
updated_at: 2026-06-04T14:57:38Z
---

Scan the maps-session.md transcript in chunks (skipping embedded images), produce a dedicated runbook 'how we rendered the maps' under tools/opentopomap-render/, map the Docker container contract and PostGIS durability, and form an opinion on workflow improvements (git-on-both-ends vs manual ssh, remote-work mode, reproducibility). Output feeds the fix of the two known z11 georeferencing bugs (hillshade SE shift; contour ribbon collapse).

## Progress (2026-06-04)

Scanned maps-session.md in chunks (images skipped). Wrote tools/opentopomap-render/RENDERING-RUNBOOK.md covering: why self-render, the server/Mac split, the Docker container contract (mounts/services/numbered scripts/patches), the Alaska-specific Copernicus DEM + chunked-contour deviations, the exact end-to-end sequence that produced the shipped z11+hillshade pack, a process post-mortem, and the two open georeferencing bugs.

Key process findings:
- Server scripts were rsync'd, not git-pulled -> untracked snapshot, repo/server can diverge.
- Hand-driven ssh + docker exec; reproducible only because written back into scripts after the fact.
- /mnt/data/srtm shared across regions -> Israel/Palestine hillshade contamination (already fixed once).
- PostGIS contour import is the expensive fragile asset (3167 chunks, hours); durability across container recreate is unverified.

Both open bugs are georeferencing in the projected-Mercator DEM chain: hillshade SE shift (Bug A) and contour horizontal-ribbon collapse (Bug B).

## Workflow hardening plan (decided 2026-06-04)

Decision: keep working LOCAL + reach server via ssh, but switch server provenance from rsync to git. No more rsync of scripts.

- [ ] Server renders from a committed SHA: 'git pull' the render-maps branch under /home/mlifshitz/tiles/AlaskaRouter instead of rsync; mount the git checkout's scripts/ at /alaskarouter-scripts.
- [ ] Stamp the render commit SHA into alaska-pack.manifest.json so each pack is traceable to source.
- [ ] Region-isolated data dirs (/mnt/data/<region>/srtm/...) + pre-render assert that style-facing rasters' gdalinfo coverage intersects the region bbox (would have caught the Israel-hillshade-in-Alaska contamination before shipping).
- [ ] pg_dump / snapshot the contour PostGIS DB once good; VERIFY (not assume) what survives a container recreate before touching the container again.

Bug beans opened: AlaskaRouter-lg59 (hillshade SE shift), AlaskaRouter-6fop (contour ribbon).
