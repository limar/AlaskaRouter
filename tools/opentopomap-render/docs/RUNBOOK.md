# How We Rendered the Maps (architecture & post-mortem)

> **Want to actually render something?** Start with [../BOOTSTRAP.md](../BOOTSTRAP.md)
> (zero-to-pack) and the **Makefile** (`make render-region REGION=...`). Hit a
> wall? [TROUBLESHOOTING.md](TROUBLESHOOTING.md). This document is the *why* —
> architecture, the machine split, and the post-mortem — not the step-by-step.

A post-mortem for the self-rendered OpenTopoMap pipeline that produced the Alaska
**z11 + hillshade** layer bundled in `AlaskaRouter/Resources/alaska-pack.pmtiles`.

This document was reconstructed from the `render-maps` session transcript and the
bean history of [`AlaskaRouter-6ihk`](../../.beans) (the render pipeline) and
`AlaskaRouter-2ptw` (the "Alaska needs closer-look detail" driver). It exists so
the next render is reproducible and so the two known bugs can be fixed against a
clear mental model rather than transcript archaeology.

---

## 1. Why we self-render

We originally shipped Alaska tiles by **scraping public OpenTopoMap PNGs**. That
was paused at ~2,345 tiles because OSM's tile-usage policy forbids bulk archival
of the volunteer tile server. The legal + repeatable path is to **render
OpenTopoMap ourselves** from OSM + a DEM, using OpenTopoMap's own Mapnik/CartoCSS
stack. That same pipeline is also the long-term enabler for label overrides
(Israel low-zoom, Falklands/Malvinas) — the original purpose of `6ihk`.

## 2. The machines and the split

| Role | Machine | Notes |
|------|---------|-------|
| Orchestration, tests, packaging code, app | **Local Mac** (this repo) | `arm64`; the OTM image is `amd64`, so local container runs are emulated/slow — fine for smoke tests only. |
| Heavy render: OSM import, DEM, contours, Tirex/Mapnik, MBTiles | **Linux server** `sol-icomp-03.lab.gdc.il.infinidat.com` | Docker 26.1.3, ~1.5 TB free on `/home`, 32 CPUs, ~754 GiB RAM. Workspace: `/home/mlifshitz/tiles/AlaskaRouter`. |

Rule of thumb established in the session: **the server does everything expensive;
the Mac only receives the final MBTiles/PMTiles artifact.**

> ⚠️ **Provenance gap (see §6):** scripts were pushed to the server with `rsync`,
> not `git pull`. The server has an untracked snapshot mounted into the container
> at `/alaskarouter-scripts`. The repo and the server can silently diverge.

## 3. The Docker container contract

Image: `jhassler/otm-docker:latest` (a wrapper around `der-stefan/OpenTopoMap`'s
Mapnik renderer). Compose file: `config/docker-compose.otm.yml`.

**Mounts the image actually expects** (learned painfully — the image uses
`/mnt/...`, *not* `/data`):

| Host (under workspace `data/docker/`) | Container | Purpose |
|---|---|---|
| `data/docker/data` | `/mnt/data` | `osmdata.pbf`, `srtm/` (DEM + derivatives + contours), water polygons |
| `data/docker/tablespace` | `/mnt/db` | PostGIS tablespace + `osm2pgsql` flat-nodes store |
| `data/osm` (ro) | `/osm` | source PBFs; `osmdata.pbf` symlinks to `/osm/<region>.osm.pbf` |
| repo `scripts/` (ro) | `/alaskarouter-scripts` | our Alaska-specific DEM/contour scripts |

**Services inside the container:** PostgreSQL 10 + PostGIS, Apache + `mod_tile`,
Tirex (master + backend-manager) driving Mapnik. Tiles served on the host at
`http://127.0.0.1:8088/otm/{z}/{x}/{y}.png` (compose publishes
`127.0.0.1:${OTM_HTTP_PORT:-8088}:80`, localhost-only — host port 8080 is
reserved for other services). Inside the container the service is on port 80.
Tile cache lives at `/mnt/tiles` (`/var/lib/tirex/tiles` → `/mnt/tiles`), which
is **not** a bind mount — it is wiped on container recreate.

> ⚠️ **Container recreate is fragile — `docker compose down/up` breaks PostgreSQL
> until repaired (data is safe, config is not).** The DB data is on host ZFS bind
> mounts (`data/docker/db` → `/var/lib/postgresql`, `data/docker/tablespace` →
> `/mnt/db`) and survives recreate. But the image ships **only** `postgresql.conf`
> in `/etc/postgresql/10/main`; `pg_hba.conf`, `pg_ident.conf`, and `conf.d/` are
> created at first run in the container's **ephemeral** layer, so a recreate loses
> them and PG refuses to boot (`could not open configuration directory conf.d` →
> then `could not load pg_hba.conf`). Recovery (verified 2026-06-04): start the
> container, then inside it recreate `/etc/postgresql/10/main/{conf.d,
> pg_hba.conf,pg_ident.conf,start.conf}` (PG port isn't published, so localhost/
> socket `trust` is fine), `chown -R postgres:postgres`, and let the init's retry
> bring PG up. Also lost on recreate and restored by `otm-docker.sh deps`:
> `python-gdal` helpers, `/mnt/tiles` dirs, the DEM helper patch, tirex.
> **TODO (hardening):** persist a complete `/etc/postgresql` via bind mount, or
> have the startup self-heal these files, so recreate is safe unattended.

**The image's numbered first-run scripts (run once, in order):**

1. `00_setup_database.sh` — role, PostGIS extension, grants.
2. `01_download_water_polys.sh` — downloads water polygons (the big one: ~882 MiB
   archive, ~42 min). Downloaded **inside the container** — preserve it to the
   host mount or you re-pay on recreate.
3. `02_import_osm_data.sh` — `osm2pgsql` import of `osmdata.pbf` into PostGIS.
4. `03_dem_hillshade.sh` — SRTM → hillshade/relief. **Replaced for Alaska** by our
   `prepare-copernicus-dem.sh` (high-latitude DEM, see §4).
5. `04_preprocess_osm_data.sh` — low-zoom generalized tables/functions.
6. `05_dem_contours1.sh` / `06_dem_contours2.sh` — generate + import contours.
   **Replaced for Alaska** by `prepare-copernicus-contours.sh` +
   `import-contours-in-chunks.py` (see §4).

**Container patches we had to apply (`ensure-otm-deps.sh` / `otm-docker.sh deps`):**
- Install `python-gdal` so legacy `gdal_fillnodata.py` / `gdal_merge.py` exist on PATH.
- Create/chown `/mnt/tiles/opentopomap` *before* Tirex starts, or Mapnik skips the
  style at boot and every render returns `404` / "map style opentopomap is not known".
- After any DB/data change, restart `tirex-backend-manager` + `tirex-master` so the
  style reloads — otherwise stale "style unknown" errors.

## 4. The Alaska-specific deviations (this is where the bugs live)

Standard OTM uses SRTM (geographic, EPSG:4326). Alaska broke two assumptions:

**DEM source — SRTM doesn't cover Alaska.** ~600 of Alaska's 1,050 one-degree
cells are north of 60°N, outside standard SRTM. We switched to **Copernicus
GLO-30 COGs** (public AWS bucket, 1°×1° COGs):
- `plan-copernicus-dem.py` / `fetch-copernicus-dem.py` — list + resumably fetch
  COGs (404 = ocean/no-data, non-fatal).
- `prepare-copernicus-dem.sh` — builds the OTM-expected `warp-*`, `relief-*`,
  `hillshade-*` rasters. **Reprojects everything to spherical Mercator**
  (`+proj=merc +ellps=sphere +R=6378137`). Notable hacks:
  - Feeds individual COGs to `gdalwarp` (not one mosaic) to dodge GDAL 2.4
    integer overflow on a full-Alaska 30 m raster.
  - `DEM_TARGET_EXTENT` constrains the warp (`-180 51 -130 72`) — without it
    `gdalwarp` produced a full-world Mercator strip.
  - `DEM_DERIVATIVES_ONLY=1` regenerates hillshade/relief from existing warps.

**Contours — `phyghtmap` run on the projected warp.** `prepare-copernicus-contours.sh`
retiles `warp-60.tif` (5000 px tiles) and runs `phyghtmap` per tile, then
`import-contours-in-chunks.py` imports them one/few PBFs per `osm2pgsql` process.
This chunking exists because the all-at-once import **segfaulted** and later hit
PostgreSQL's **1 GiB single-allocation limit** (`invalid memory alloc request
size 1073741824`) on pathologically dense/long contour ways. Final settings:
`CONTOUR_TILE_SIZE=5000`, `MAX_NODES_PER_TILE=1e6`, `MAX_NODES_PER_WAY=2000`,
`ID_STRIDE=5e6`. The bounded import completed at **3167/3167** chunks.

## 5. End-to-end sequence that produced the shipped pack

On the server (`/home/mlifshitz/tiles/AlaskaRouter`):

```
# inputs
fetch-osm.sh alaska_z11                     # Geofabrik alaska-latest.osm.pbf
fetch-copernicus-dem.py alaska_z11          # ~596 COGs into data/docker/data/copernicus-dem/
prepare-otm-docker.sh alaska_z11            # wire mounts/symlinks
otm-docker.sh up && otm-docker.sh deps      # start container, apply patches

# in-container first run (00,01,02,04) + Alaska DEM/contours
DEM_TARGET_EXTENT="-180 51 -130 72" prepare-copernicus-dem.sh
prepare-copernicus-contours.sh
import-contours-in-chunks.py --batch-size 8 ...

# render → export → pack
tirex-batch -p 8 -d map=opentopomap bbox=-180,51,-130,72 z=11   # 1225 metatiles
export-region-tiles.py alaska_z11 --force --jobs 16             # 74,955 PNGs
pack-mbtiles.py                                                 # alaska_z11.mbtiles
```

Then locally:

```
rsync -az --partial -e ssh sol-icomp-03:.../alaska_z11.mbtiles .
pmtiles convert alaska_z11.mbtiles alaska_z11.pmtiles
# extract existing pack to z0..10, merge with z11, set maxzoom=11
pmtiles ... merge → alaska-pack.pmtiles  (installed into Resources/)
# update alaska-pack.manifest.json (version, byte_size, coverage maxzoom 11)
```

Result: 1.1 GB pack, maxzoom 11, 101,631 tiles. Galbraith sample `11/173/482`
verifies as the hillshaded 20 KiB PNG (sha `ada28d4…`).

## 6. Process post-mortem — what was fragile, what to change

**What worked well**
- Tested, deterministic helper scripts (estimate/plan/fetch/pack) with unit tests.
- Small committed slices with bean-ID commit messages; the bean log is an
  excellent narrative audit trail.
- Server-for-heavy / Mac-for-packaging split is the right shape.

**What was fragile / cost us**
1. **Scripts pushed by `rsync`, not git.** The server runs an untracked snapshot.
   No guarantee the repo matches what produced the tiles → hard to reproduce or
   trust a fix. **Fix: the server should `git pull` a branch; render only from a
   committed SHA, and record that SHA in the pack manifest.**
2. **Hand-driven `ssh` + `docker exec`.** Long imperative sessions, lots of
   live-debugging container-contract mismatches. Reproducible only because they
   were written back into scripts after the fact. **Fix: drive the server through
   Claude Code remote-work mode (or a single `make`-style entrypoint) so the
   sequence is one tracked command, not a transcript.**
3. **Region cross-contamination.** `/mnt/data/srtm/` is shared across regions with
   no isolation — the first z11 render shipped with **Israel/Palestine hillshade**
   because the stale `hillshade-30-jpeg.tif` was never region-scoped. **Fix:
   per-region data dirs (`/mnt/data/<region>/srtm/...`) and a pre-render assert
   that `gdalinfo` coverage of the style-facing rasters intersects the region bbox.**
4. **PostGIS durability is the expensive, fragile asset.** The contour import is
   **hours** of work (3167 chunks). Whether it survives depends on where the DB
   cluster physically lives:
   - Container **stop/start**: safe *iff* the cluster + tablespace are on the
     persistent bind mounts (`/mnt/db`, and `/var/lib/postgresql` which the image
     persists). The image keeps `/etc/postgresql` *inside the image layer*, so a
     recreate can leave data without its matching config.
   - Container **`rm`/recreate**: **destroys** anything in the writable layer.
     Re-import = hours.
   - **Action before touching that container again:** verify with
     `docker compose ... config` + `docker inspect` exactly which paths are bind
     mounts vs. ephemeral, and `pg_dump`/snapshot the contour DB once it's good.
     Treat "what survives a recreate" as *verified*, not *assumed*.

**Reuse outlook**
- The pipeline generalizes to v2+ regions and to the label-override POC with
  little change *if* §6.1–6.3 are fixed (git provenance, single entrypoint,
  region isolation).
- HD corridor packs (Dalton/Denali/Kenai z12–13) reuse this unchanged except for
  `regions.json` bbox/zoom — but only after the georeferencing bugs below are fixed.

## 7. The georeferencing/import bugs — all RESOLVED

The original z11 render had a chain of bugs, all now fixed (and shipping):

- **Hillshade shifted SE** (AlaskaRouter-lg59): the DEM was warped to PROJ's
  `+ellps=sphere` (radius 6370997) instead of EPSG:3857 (6378137). Fixed:
  `-t_srs EPSG:3857` for the hillshade/relief warps.
- **Contours collapsed into a ribbon** (AlaskaRouter-6fop): `phyghtmap` was fed a
  projected Mercator DEM. Fixed: `warp-60` is now geographic EPSG:4326.
- **Contours spidernetted in high-id tiles** (6fop, the deep one): osm2pgsql
  1.2.0 mishandles node ids >2³². Fixed by importing through the **osm2pgsql 1.11
  sidecar** (`make import`), which also forced sorting all per-tile PBFs into one
  file via `osmium sort` (1.11 segfaults on many `--create` inputs and on
  `--append`).

Full failure-mode details and recovery steps live in
[docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md). The current, reproducible pipeline
is the **Makefile** (`make render-region REGION=...`) — see
[../BOOTSTRAP.md](../BOOTSTRAP.md). The §5 sequence below is the original
hand-run history; the import stage there is superseded by the sidecar.
