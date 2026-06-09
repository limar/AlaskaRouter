---
# AlaskaRouter-msgi
title: Build a pinned OTM render image (Dockerfile) to kill manual bootstrap + recreate fragility
status: in-progress
type: task
priority: normal
created_at: 2026-06-04T17:04:26Z
updated_at: 2026-06-09T16:38:27Z
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
- [ ] Bake recreate-safety config (pg_hba/pg_ident/conf.d, tuned postgresql.conf) into a pinned render image (still desirable, separate from the importer)
