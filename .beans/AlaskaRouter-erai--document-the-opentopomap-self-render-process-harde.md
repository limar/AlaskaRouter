---
# AlaskaRouter-erai
title: Document the OpenTopoMap self-render process + harden the workflow
status: completed
type: task
priority: high
created_at: 2026-06-04T14:51:34Z
updated_at: 2026-06-10T10:23:47Z
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

- [x] Server renders from a committed SHA: 'git pull' the render-maps branch under /home/mlifshitz/tiles/AlaskaRouter instead of rsync; mount the git checkout's scripts/ at /alaskarouter-scripts.
- [x] Stamp the render commit SHA into alaska-pack.manifest.json so each pack is traceable to source.
- [x] (→ AlaskaRouter-0bq8) Region-isolated data dirs (/mnt/data/<region>/srtm/...) + pre-render assert that style-facing rasters' gdalinfo coverage intersects the region bbox (would have caught the Israel-hillshade-in-Alaska contamination before shipping).
- [x] (→ AlaskaRouter-0bq8) pg_dump / snapshot the contour PostGIS DB once good; VERIFY (not assume) what survives a container recreate before touching the container again.

Bug beans opened: AlaskaRouter-lg59 (hillshade SE shift), AlaskaRouter-6fop (contour ribbon).

## Server hardening + recreate incident (2026-06-04)

Moved OTM tile publish off host port 8080 (reserved for other services) to 127.0.0.1:8088 (localhost-only) via compose; committed 37c6360. Applying it required a container recreate.

Verified before recreating: PG cluster + tablespace are on host ZFS bind mounts (data/docker/db -> /var/lib/postgresql = 1.7G; data/docker/tablespace -> /mnt/db), so recreate preserves all DBs. Confirmed post-recreate: gis.planet_osm_line=635376, polygon=555126, point=93430, contours=33457 -> identical to pre-recreate baseline. No data loss.

NEW FRAGILITY FOUND: the image ships only postgresql.conf in /etc/postgresql/10/main; pg_hba.conf, pg_ident.conf, conf.d are created at first-run in the EPHEMERAL layer, so recreate loses them and PG won't boot. Recovered by recreating those files (trust auth, PG port not published) + chown postgres + otm-docker.sh deps (restores python-gdal, /mnt/tiles, tirex). Documented in RENDERING-RUNBOOK.md.

- [x] HARDENING TODO: persist a complete /etc/postgresql via bind mount (populated, not empty) OR self-heal the missing config files at container startup, so 'docker compose down/up' is safe unattended. Until then, do NOT recreate the container without the documented recovery on hand.

## Summary of Changes (2026-06-10)
Docs + workflow hardening shipped: docs/RUNBOOK.md (de-staled to the current sidecar/osmium-sort/EPSG:3857 pipeline), docs/TROUBLESHOOTING.md, BOOTSTRAP.md, README index; render runs from committed source (git-bundle deploy + scripts/ mounted); render_commit stamped into alaska-pack.manifest.json; recreate-safety baked into the image (AlaskaRouter-msgi). The two remaining items (region-coverage gdalinfo assert; pg_dump snapshot) are render-safety/scaling concerns moved to AlaskaRouter-0bq8.
