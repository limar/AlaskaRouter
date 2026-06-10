---
# AlaskaRouter-msgi
title: Build a pinned OTM render image (Dockerfile) to kill manual bootstrap + recreate fragility
status: completed
type: task
priority: normal
created_at: 2026-06-04T17:04:26Z
updated_at: 2026-06-10T09:57:37Z
parent: AlaskaRouter-6ihk
---

## Problem
The render stack runs on upstream jhassler/otm-docker:latest, which needs manual runtime bootstrap and is fragile on recreate:
- python-gdal helpers (gdal_fillnodata.py/gdal_merge.py) not in image -> installed at runtime.
- /etc/postgresql/10/main ships only postgresql.conf; pg_hba.conf/pg_ident.conf/conf.d are created at first run in the EPHEMERAL layer -> a 'docker compose down/up' breaks PostgreSQL until manually repaired (incident 2026-06-04; data was safe on bind mounts, config was not).
- /mnt/tiles dirs + DEM helper patch + tirex restart all re-done by otm-docker.sh deps after each recreate.

## Options
1. Thin Dockerfile FROM jhassler/otm-docker (pinned by digest) that bakes: python-gdal, the gdal helper patch, a complete /etc/postgresql/10/main config (pg_hba/pg_ident/conf.d/start.conf), /mnt/tiles dirs. Recreate-safe, reproducible, provenance in our repo. Pin the base digest so we are NOT rebasing on upstream every time; update deliberately.
2. Keep upstream image + an idempotent entrypoint/init wrapper (mounted) that self-heals the same things on every start. Lighter, no image to build/host, but still relies on a wrapper.
3. Status quo (manual ensure-otm-deps + documented recovery). Works, fragile.

## Recommendation
Option 1 (pinned thin Dockerfile) — best reproducibility + recreate-safety + provenance, and pinning the base digest means we control upstream updates rather than tracking latest. Option 2 is an acceptable lighter alternative.

## Relates to
- [[erai]] workflow hardening (this is the concrete fix for the recreate-fragility TODO).
- RENDERING-RUNBOOK.md container-recreate warning.

## Sidecar approach built + validated (2026-06-09)
Decision: rather than rebase the whole OTM Mapnik stack (bionic caps osm2pgsql at 1.2.0; newer needs newer PROJ -> full OS rebase), run a MODERN osm2pgsql as a sidecar against the existing PostGIS. osm2pgsql and Mapnik are independent stages.

Built tools/opentopomap-render/docker/osm2pgsql-sidecar/Dockerfile (FROM ubuntu:24.04, apt osm2pgsql 1.11.0 — keeps --output=pgsql so the OTM planet_osm_* schema is unchanged, native 64-bit ids, --number-processes). Validated on server:
- osm2pgsql 1.11.0 builds.
- Reaches render PG via 'docker run --network container:alaskarouter-otm' on 127.0.0.1 (PostGIS 2.5.2) — NO listen_addresses change, no extra network exposure. pg_hba already trusts 127.0.0.1.
- Sees the contour PBFs via the shared /mnt/data mount.
- libpq tools honor PGHOST/PGPORT/PGUSER env -> no import-script connection changes needed.

Implication: 1.11 fixes the 2^32 spidernet (AlaskaRouter-6fop) at the import layer. The per-tile-stride/contiguous-id workarounds AND the 1.2.0 chunked-import workaround are unnecessary; 1.11 can import all PBFs in one parallel invocation. Coarsening becomes a size/perf choice only.

- [x] Build modern osm2pgsql sidecar image + validate connectivity/data access
- [x] POC: 1.11 sidecar re-import of the broken southern band -> spidernets gone, 693s, ~25x faster
- [x] Bake recreate-safety config into a pinned render image: docker/otm-render/Dockerfile FROM jhassler/otm-docker@sha256:adbe421f... (pinned), bakes complete /etc/postgresql/10/main + python-gdal. Built + verified (files present, PG starts). Compose defaults to it. Makefile: render-image/images/save-images/load-images. Archived to data/images/*.tar.gz (own the bytes). REMAINING: switch the production container to it (recreate -- safe now since config is baked) + optionally publish the image tarball.

## Summary of Changes (2026-06-10) -- DONE
Achieved the three layers of 'own a reliable render image':
1. PIN: docker/otm-render/Dockerfile FROM jhassler/otm-docker@sha256:adbe421f... (digest, not :latest).
2. RECREATE-SAFETY: bakes a complete /etc/postgresql/10/main config + python-gdal so 'docker compose down/up' no longer breaks PostgreSQL. Built + verified (files present, PG boots, gdal helpers present). Compose defaults to alaskarouter/otm-render:2026-06-10 with a build context; Makefile render-image/images/save-images/load-images.
3. OWN THE SOURCE: instead of a 2 GB image tarball (rejected), vendored the ~1.9 MB upstream SOURCE (github.com/lukey78/otm-docker @ a024111) under third_party/ with PROVENANCE.md + the fragile phyghtmap .deb. Gives us the build blueprint + the OTM cartography assets even if Docker Hub and the upstream GitHub vanish.

Deferred by user: switch the PRODUCTION container onto the new image ('wait till we need it for real'). The compose already points to it, so the next container recreate applies it automatically. License clearance before any public/OSS release tracked in AlaskaRouter-1tpz.
