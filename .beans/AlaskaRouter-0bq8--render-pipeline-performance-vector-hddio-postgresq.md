---
# AlaskaRouter-0bq8
title: Render-pipeline performance vector (HDD/IO, PostgreSQL, osm2pgsql) for multi-region scaling
status: in-progress
type: task
priority: normal
created_at: 2026-06-07T15:07:05Z
updated_at: 2026-06-09T16:25:40Z
parent: AlaskaRouter-6ihk
---

## Context
Imports (contours especially) are IO-bound on the HDD ZFS pool (no SSD/NVMe). But the box has 753 GB RAM + 32 cores, which we are barely using. Goal: make per-region imports fast + reproducible for other countries/regions. Benchmarks reviewed: https://wiki.openstreetmap.org/wiki/Osm2pgsql/benchmarks

## Current state (measured 2026-06-07)
- PostgreSQL 10 on the IMAGE DEFAULTS (shared_buffers 128MB, maintenance_work_mem 64MB, fsync on, synchronous_commit on, full_page_writes on, tiny WAL). Recreated with vanilla conf during the container-recreate recovery.
- ZFS zfspool/home: recordsize=128K, compression=lz4 (good), sync=standard, atime=off (good), primarycache=all, logbias=latency.
- RAM 753 GB; ZFS ARC size ~339 GB (c_max ~377 GB). flat-nodes ~143 GB on the HDD pool.
- osm2pgsql 1.2.0 (2019) from jhassler/otm-docker. No --number-processes passed.
- Contour workload is self-inflicted heavy: 1.56B synthetic nodes statewide at 0.0005deg / -s 10.

## Tier 1 — free, biggest wins (no new hardware; use the RAM)
- [ ] flat-nodes on tmpfs (RAM): put the ~143 GB flat-nodes file on a tmpfs mount (/dev/shm or dedicated). It is ephemeral (rebuilt each import), so RAM is ideal. Eliminates the HDD random-IO penalty for the node store entirely — the single biggest lever for our node-heavy contour imports. Budget: 150 GB tmpfs + 64 GB shared_buffers + osm2pgsql cache << 753 GB.
- [ ] PostgreSQL import-time tuning (safe because imports are fully reproducible/restartable): fsync=off, synchronous_commit=off, full_page_writes=off, maintenance_work_mem=24GB, shared_buffers=64GB, work_mem=2GB, effective_cache_size=500GB, max_wal_size=64GB, checkpoint_timeout=30min, autovacuum=off during import, max_parallel_workers=32, max_worker_processes=32. Revert fsync/synchronous_commit to safe values for serving.
- [ ] ZFS: sync=disabled during import (kills ZIL sync penalty on HDD; safe with redo-able imports), logbias=throughput; consider a dedicated PG dataset with recordsize=8K (PG page size) to cut read/write amplification (128K default amplifies).
- [ ] osm2pgsql --number-processes 32 for parallel index build; consider dropping --cache (rely on flat-nodes-in-RAM + ARC) to free memory.

## Tier 2 — medium effort
- [ ] Newer osm2pgsql (1.2.0 -> 1.11/2.x): ~2-3x faster middle + better parallelism. Bake into the pinned image (see AlaskaRouter-msgi).
- [ ] Reduce contour node volume at the source: coarsen the contour DEM (warp-60) from 0.0005deg to ~0.001deg (~90 m). ~4x fewer nodes (1.56B -> ~0.4B) => ~4x less import IO + smaller packs, with negligible z11 visual loss. Per-region scaling win and directly attacks the HDD pain. Re-check contour appearance after.

## Tier 3 — hardware
- [ ] A single consumer NVMe (1-2 TB) for flat-nodes + PG data would end the IO discussion (planet imports go from days to ~10 h on NVMe per the benchmarks). Until then, tmpfs (Tier 1) is the no-hardware substitute.

## Make it reproducible
Bake the tuned postgresql.conf + newer osm2pgsql + the tmpfs-flat-nodes + ZFS conventions into the pinned render image (AlaskaRouter-msgi) and a per-region config, so every new country/region import is fast and identical.

## Notes
- Do NOT apply mid-run to the current import; these target future/region imports.
- Relates to: AlaskaRouter-msgi (pinned image), AlaskaRouter-r1cf (region packs).
