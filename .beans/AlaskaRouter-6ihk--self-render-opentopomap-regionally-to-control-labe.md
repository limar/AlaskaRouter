---
# AlaskaRouter-6ihk
title: Self-render OpenTopoMap regionally to control labels at render time
status: in-progress
type: feature
priority: high
created_at: 2026-05-23T19:29:19Z
updated_at: 2026-06-07T08:46:30Z
---

## Why

OpenTopoMap rasterizes labels into pixels using OSM data + their CartoCSS. Some of those labels carry political opinions we don't want to ship verbatim:

- **Falkland Islands / Islas Malvinas** — locale-dependent naming. Argentine users expect Islas Malvinas.
- **Israel** — OSM has it; OpenTopoMap's CartoCSS suppresses the label at low zoom. Need to surface it.
- **Bilingual local-script + English** stacking at world zoom — visually loud, will multiply across v2+ regions.

We considered:
- (rejected) **Halo-masking vector labels over the existing raster** — visible artifacts at edges
- (rejected) **Switch basemap to Stamen Terrain (Background)** — user's verdict: "doesn't look very competitive" vs OpenTopoMap's "love my planet" emotional anchor
- (chosen) **Self-render OpenTopoMap on our infrastructure, regionally, with our own label overrides**

## Hardware available

- Linux server, ~20 CPUs, hundreds of GB RAM, multi-TB HDD (no SSD)
- SSH + Claude Code remote-work mode

HDD slows the one-time PostGIS import (10–20× vs SSD) but doesn't block. Rendering after import is mostly sequential reads — HDD is fine.

## Architecture (draft)

### Pipeline

```
        Geofabrik regional PBF      OpenTopoMap CartoCSS (der-stefan/OpenTopoMap)
                │                              │
       osmium tags-modify ◀── overrides.yml    │
                │                              │
        osm2pgsql import ──────► PostGIS ◀─────┘
                │                              │
        SRTM hillshade preparation             │
                │                              │
                └────────► mapnik (Python) ────┘
                                  │
                          rendered PNG tiles per (z,x,y)
                                  │
                          go-pmtiles edit
                                  │
                          patched alaska-pack.pmtiles
```

### Repo layout

```
tools/opentopomap-render/
  README.md
  config/
    overrides.yml          ← label rewrites, keyed by region + OSM feature
    tile-targets.yml       ← which (z,x,y) tiles to re-render per region
  scripts/
    install.sh             ← one-time toolchain install on server
    fetch-osm.sh           ← Geofabrik extracts
    apply-overrides.sh     ← osmium tags-modify pass
    import.sh              ← osm2pgsql → PostGIS
    fetch-srtm.sh          ← SRTM elevation data for hillshade
    render-tiles.sh        ← mapnik render the target tiles
    splice-into-pack.sh    ← go-pmtiles edit, runs locally
  cartocss/
    OpenTopoMap/           ← git submodule of der-stefan/OpenTopoMap
    patches/               ← *.mss patches (e.g. show-israel-at-low-zoom.diff)
  data/                    ← gitignored
    osm/                   ← raw + edited PBFs
    srtm/                  ← elevation
    tiles/<region>/<z>/<x>/<y>.png
```

### Region-scope strategy

Each `region pack` = one Geofabrik extract → one PostGIS database → renders any tile inside that region.

- **Per-region world-zoom tiles** (z=0–5) re-rendered selectively (just the ones with offending labels) — minimal scope.
- **Per-region detail tiles** (z=6–10) re-rendered for that region's coverage area.
- Regions that don't have political-label problems (e.g. Alaska detail) keep the upstream-scraped tiles unchanged.

### POC scope (smallest end-to-end demo)

1. Set up toolchain on the linux server.
2. Import a small OSM extract — **Israel/Palestine area** (~80 MB PBF, fastest POC).
3. Apply one label override: ensure "Israel" label appears at z=3 via a CartoCSS patch on the admin0-labels layer.
4. Render ONE tile at z=3 covering the eastern Mediterranean.
5. Visually diff against the same tile on opentopomap.org.
6. Splice the rendered tile into a local copy of our PMTiles pack.
7. Build the app + verify in the simulator.

### Open architectural questions

- **PMTiles edit-in-place vs rebuild**: does `go-pmtiles` support tile-replacement, or do we extract → swap → re-pack each time?
- **SRTM data**: per-region subset vs full-world cache. ~30 GB for global SRTM3.
- **Overlay-pack vs in-place edits**: do we ship modified tiles AS PART of `alaska-pack.pmtiles`, or as a separate `regions-overlay.pmtiles` that takes priority at runtime?
- **Mapnik dep hell mitigation**: Docker image vs native install? Docker would isolate the toolchain pain and make the server setup reproducible.
- **Tile-spec consistency**: OpenTopoMap public tiles use 256px PNGs. We'd want to match exactly (tile size, projection, resampling) so spliced tiles visually align with surrounding ones.

## Plan of attack

1. **Architecture lock** — agree on the open questions, then bean-update the answers.
2. **Toolchain bootstrap** — `install.sh` on the linux server. Use Docker if it minimizes dep hell.
3. **Fetch a small OSM PBF + SRTM tile** for Israel/Palestine area.
4. **POC render** — render one z=3 tile, diff against public OpenTopoMap.
5. **Compare visually** — confirm we're producing pixel-equivalent output before adding overrides.
6. **First override** — add Israel label via CartoCSS patch, re-render, compare.
7. **Splice POC** — produce a modified PMTiles pack and verify in-app.
8. Then expand: Falklands, multi-region production pipeline.

## Out of scope (for now)

- Full-planet render (we never need this; regional is enough).
- v2+ multi-region pack architecture — uses this pipeline but is its own bean.
- Vector label overlay approach — abandoned in favor of self-render.

## Checklist

- [ ] Lock open architectural questions (PMTiles edit/rebuild, SRTM scope, overlay vs in-place, Docker vs native, tile-spec consistency)
- [ ] `tools/opentopomap-render/install.sh` — toolchain bootstrap on the linux server
- [ ] `fetch-osm.sh` — Geofabrik download with SHA verify
- [ ] `fetch-srtm.sh` — SRTM3 download
- [ ] `import.sh` — osm2pgsql → PostGIS for a small region
- [ ] `render-tiles.sh` — mapnik render a single tile from a bbox
- [ ] Visual diff between our render and opentopomap.org render of the same tile
- [ ] First label override: CartoCSS patch for Israel low-zoom visibility
- [ ] `splice-into-pack.sh` — pmtiles edit
- [ ] Verify in-app


## Architecture LOCKED (2026-05-24)

| # | Decision | Choice |
|---|---|---|
| 1 | Server install | **Docker** — Mapnik dep hell isolated. Likely fork `overv/openstreetmap-tile-server` to bootstrap. |
| 2 | PMTiles update model | **Rebuild pack each release** — deterministic pipeline takes upstream-scraped + our overrides → fresh pack. Same `release-pack.sh` workflow as today. |
| 3 | Override packaging | **In-place** in `alaska-pack.pmtiles` — no overlay pack. Override count is small enough (<100 globally) that the single-pack model wins. |
| 4 | SRTM scope | **Per-region subset, cached** to `data/srtm/<region>/`. `fetch-srtm.sh` is idempotent. |
| 5 | Tile-spec | **Pixel-equivalent with `tile.opentopomap.org/{z}/{x}/{y}.png`** — 256 px PNG, EPSG:3857, same scale denoms. Pixel-equivalence is the bar for "POC succeeded." |

## POC region: **Israel / Palestine** (smallest, fastest)

- Geofabrik PBF: `israel-and-palestine-latest.osm.pbf` (~80 MB)
- Expected import time on HDD: 1–2 hours
- First override target: surface "Israel" label at z=3 via CartoCSS patch on the admin0-labels layer (OSM has the data; OpenTopoMap's renderer suppresses it at low zoom)
- Visual success criterion: a rendered z=3 tile that's pixel-equivalent to the public OpenTopoMap tile, **except** the Israel label is present

## Driver plan

User will connect **Claude Code remote-work mode to the linux server** later today (low-load evening window). Until then this bean is paused.

When we resume:
1. Bootstrap the toolchain inside Docker on the server.
2. Pull the Israel/Palestine PBF + the matching SRTM tiles.
3. Run the first render of a single z=3 tile.
4. Visual diff against the public OpenTopoMap.

Goal for the first session: end-to-end pipeline producing one tile, no overrides applied yet — just prove we can reproduce upstream.

## Rescope (2026-05-28)

`AlaskaRouter-2ptw` now depends on this bean. The immediate production driver is
not political-label overrides; it is **legally/repeatably producing Alaska z=11
detail** without bulk-downloading public tile-server PNGs. Keep the label
override POC as a useful small render target, but prioritize the pipeline shape
needed for `alaska_z11`.

First local slice completed:

- Added `tools/opentopomap-render/README.md` with disk/bandwidth notes and the
  v1 z=11 flow.
- Added `config/regions.json` with `alaska_z11` and `israel_palestine_poc`
  render targets.
- Added `scripts/estimate-region.py`; verified `alaska_z11` = 74,955 tiles and
  `israel_palestine_poc` = 1 tile.
- Added `scripts/fetch-osm.sh` for configured Geofabrik PBF downloads.
- Added `scripts/pack-mbtiles.py` for packaging rendered `z/x/y.png` tile trees
  into MBTiles before PMTiles conversion.
- Gitignored `tools/opentopomap-render/data/` as scratch.

Next slice:

1. Build or select the Docker image that can run the OpenTopoMap Mapnik stack.
2. Clone/pin the OpenTopoMap CartoCSS source used by that image.
3. Import the tiny `israel_palestine_poc` extract first and render one z=3 tile.
4. Once a one-tile render works, run the Alaska import and z=11 render on the
   server.

## Docker Bootstrap Slice (2026-05-28)

Upstream check: the official `der-stefan/OpenTopoMap` repo says the raster
renderer is Mapnik-based and includes the files needed to build an OpenTopoMap
server. The practical Docker wrapper `lukey78/otm-docker` packages those files
and expects a project data layout containing `data/data/osmdata.pbf`,
`data/data/srtm/`, `data/db`, and `data/letsencrypt`.

Added local wrappers around that shape:

- `config/docker-compose.otm.yml` uses `jhassler/otm-docker:latest` by default,
  with an overridable `OTM_DOCKER_IMAGE`.
- `scripts/prepare-otm-docker.sh <region>` symlinks the configured PBF to the
  expected `osmdata.pbf` and creates Docker scratch directories.
- `scripts/otm-docker.sh` wraps compose up/down/logs/shell and prints the
  ordered one-time import scripts.
- `scripts/render-region-command.py <region>` prints the Tirex batch command
  for the configured bbox/zoom target.

Still missing before first rendered tile:

- SRTM source selection/fetch automation.
- Actual container import run on the server.

## DEM Planning Slice (2026-05-28)

Added `scripts/plan-srtm-cells.py <region>` and tests. The script lists
HGT-style DEM cells for a configured region and flags cells outside standard
SRTM coverage.

Findings:

- `israel_palestine_poc` needs 15 cells, all inside standard SRTM coverage.
- `alaska_z11` spans 1,050 HGT-style cells; 450 are inside standard SRTM
  coverage and 600 are north of 60 degrees, outside standard SRTM coverage.

This means the POC can proceed with normal SRTM HGT ZIP/HGT files, but the
Alaska production render needs a high-latitude DEM source decision before we
spend bandwidth on elevation data.

Still missing before first rendered tile:

- SRTM source/fetch automation for the low-latitude POC.
- High-latitude DEM source decision for Alaska.
- Actual container import run on the server.

## Local Renderer Export Slice (2026-05-28)

Added `scripts/export-region-tiles.py <region>` to copy rendered PNGs from the
local OpenTopoMap HTTP endpoint into `data/tiles/<region>/<z>/<x>/<y>.png`.
It is resumable by default, validates PNG responses, supports `--dry-run`, and
keeps the export shape directly compatible with `pack-mbtiles.py`.

Added `tests/test_export_region_tiles.py`, which starts a loopback HTTP server
and verifies that the `israel_palestine_poc` region exports exactly
`3/4/3.png`.

Still missing before first rendered tile:

- SRTM source selection/fetch automation.
- Actual container import run on the server.

## SRTM Fetch Slice (2026-05-28)

Added `scripts/fetch-srtm.py <region>` and tests. The script fetches
SRTMGL1 HGT ZIP files from the ESA public DEM mirror by default, writes them
to `data/docker/data/srtm`, validates ZIP responses, skips existing files, and
supports `--dry-run`.

The script deliberately refuses regions with cells outside standard SRTM
coverage. For the current targets:

- `israel_palestine_poc` can fetch 15 SRTMGL1 ZIPs immediately.
- `alaska_z11` still refuses because 600 of its 1,050 HGT-style cells are
  north of standard SRTM coverage.

Also corrected `export-region-tiles.py` to default to the otm-docker tile
route: `http://127.0.0.1:8080/otm`.

Still missing before first rendered tile:

- Actual container import run on the server.
- High-latitude DEM source decision for Alaska production rendering.

## POC Data Fetch Slice (2026-05-28)

Fetched the small POC inputs locally:

- `data/osm/israel_palestine_poc.osm.pbf`: Geofabrik Israel/Palestine extract,
  116 MiB download, 128 MiB on disk with checksum sidecar.
- `data/docker/data/srtm/`: 12 SRTMGL1 ZIP files, 94 MiB on disk.

Three SRTMGL1 cells inside the bbox return HTTP 404 from the ESA mirror:
`N32E033`, `N33E033`, and `N33E034`. The fetcher now treats 404s as nonfatal
absent/no-data cells by default and offers `--strict-missing` for audits.

Also added curl timeouts to `fetch-osm.sh` so checksum sidecar requests cannot
silently block a completed PBF fetch.

Still missing before first rendered tile:

- Prepare Docker layout for `israel_palestine_poc`.
- Start the renderer container and run the import scripts.
- High-latitude DEM source decision for Alaska production rendering.

## Docker Mount Fix (2026-05-28)

Started the otm-docker container and verified the initial service startup. The
container created its PostgreSQL cluster and Apache/mod_tile exposed `/otm` on
port 8080.

This exposed a wrapper bug: `osmdata.pbf` originally symlinked to a host path
outside the `/data` bind mount, so the link was broken inside the container.
Fixed the compose file to mount `data/osm` read-only at `/osm` and changed
`prepare-otm-docker.sh` to point `osmdata.pbf` at `/osm/<region>.osm.pbf`.

The first recreate also exposed a limitation in this Docker image: it persists
`/var/lib/postgresql`, but keeps `/etc/postgresql` inside the container image.
Until we add a durable import strategy, treat `data/docker/db` as disposable
scratch if the container is recreated before the real server import.

Still missing before first rendered tile:

- Re-prepare Docker layout and re-check the mounted POC PBF inside the
  container.
- Run the import scripts.
- High-latitude DEM source decision for Alaska production rendering.

## Docker Path Fix (2026-05-28)

Ran the first two otm-docker setup scripts locally:

- `00_setup_database.sh` completed.
- `01_download_water_polys.sh` downloaded and unpacked the upstream water
  polygon sources. The full water polygon archive was 882 MiB and took about
  42 minutes locally; the unpacked host copy is 1.2 GiB.

`02_import_osm_data.sh` exposed another image contract mismatch: the image
expects `osmdata.pbf` under `/mnt/data` and tablespace scratch under `/mnt/db`.
Copied the downloaded `water-polygons` tree out of the live container before
recreating it, then updated compose to mount:

- `data/docker/data` -> `/mnt/data`
- `data/docker/tablespace` -> `/mnt/db`
- `data/osm` -> `/osm` read-only

Still missing before first rendered tile:

- Recreate the container with the corrected `/mnt/data` and `/mnt/db` mounts.
- Re-run/import from the persisted water polygon and POC PBF data.
- High-latitude DEM source decision for Alaska production rendering.


## GDAL Helper Patch (2026-05-28)

`03_dem_hillshade.sh` reached SRTM unpacking, then failed because the Docker image
had `gdal-bin`/`python3-gdal` but not the legacy helper scripts used by
OpenTopoMap: `gdal_fillnodata.py` and `gdal_merge.py`. Installing the image
package `python-gdal` provides those scripts at `/usr/bin`.

Added `tools/opentopomap-render/scripts/ensure-otm-deps.sh` and the
`otm-docker.sh deps` wrapper so this patch/check is an explicit bootstrap step
before DEM preprocessing.

Still missing before first rendered tile:

- Rerun `03_dem_hillshade.sh` from clean SRTM scratch.
- Run `04_preprocess_osm_data.sh`, `05_dem_contours1.sh`, and
  `06_dem_contours2.sh`.
- Render and export the first POC tile.


## First Rendered POC Tile (2026-05-28)

Completed the local `israel_palestine_poc` otm-docker pipeline through:

- `03_dem_hillshade.sh`
- `04_preprocess_osm_data.sh`
- `05_dem_contours1.sh`
- `06_dem_contours2.sh`
- `tirex-batch -p 1 -d map=opentopomap bbox=33.9,29.3,36.0,33.4 z=3`
- `export-region-tiles.py israel_palestine_poc --force`
- `pack-mbtiles.py` into `data/mbtiles/israel_palestine_poc.mbtiles`

The render initially returned 404 because Tirex master listed `opentopomap`, but
the Mapnik backend skipped the style at startup: `/var/lib/tirex/tiles` points
to `/mnt/tiles`, and `/mnt/tiles/opentopomap` did not exist yet. Extended
`ensure-otm-deps.sh` to create/chown the Tirex tile cache directories and
restart `tirex-backend-manager` plus `tirex-master`. After rerunning
`otm-docker.sh deps`, the same render request succeeded (`success=1` in
`/var/log/tirex/jobs.log`) and export wrote `3/4/3.png`.

Validation artifacts are gitignored under `tools/opentopomap-render/data/`:

- `data/tiles/israel_palestine_poc/3/4/3.png`: PNG, 256x256, 4.5 KiB.
- `data/mbtiles/israel_palestine_poc.mbtiles`: SQLite MBTiles, 1 tile, 24 KiB.

Still missing before Alaska production z11 render:

- Decide and fetch a high-latitude Alaska DEM source; standard SRTM does not
  cover most of Alaska.
- Run the same server-side import/render/export sequence for `alaska_z11`.
- Apply label overrides and visually diff against upstream OpenTopoMap tiles.


## Alaska Server Work Plan (2026-05-28)

The production render should move to the Linux server instead of the local
Mac. The available server profile is sufficient for the expensive path: Docker
ready, `jhassler/otm-docker` already pulled, 669 GiB free disk, 32 CPUs, and
754 GiB RAM. Local work should remain orchestration/tests; copy back only the
final MBTiles/PMTiles artifact.

Added the high-latitude DEM path for Alaska:

- `plan-copernicus-dem.py` lists Copernicus GLO-30 one-degree COG URLs for a
  configured region. `alaska_z11` plans 1,050 possible cells before 404/no-data
  filtering.
- `fetch-copernicus-dem.py` downloads those COGs resumably into
  `data/docker/data/copernicus-dem/` and treats 404 cells as missing by default.
- `prepare-copernicus-dem.sh` runs inside otm-docker and builds the same
  `raw.tif`, `warp-*`, `relief-*`, and `hillshade-*` products that the
  OpenTopoMap style expects under `/mnt/data/srtm`. This replaces
  `03_dem_hillshade.sh` for Alaska.
- Docker compose now mounts host scripts read-only at `/alaskarouter-scripts`
  so the server container can run the Alaska-specific DEM prep script.
- README now contains the server sequence and disk/bandwidth expectations.

Validation:

- `python3 -m unittest discover tools/opentopomap-render/tests`
- `python3 -m py_compile tools/opentopomap-render/scripts/plan-copernicus-dem.py tools/opentopomap-render/scripts/fetch-copernicus-dem.py`
- `bash -n tools/opentopomap-render/scripts/prepare-copernicus-dem.sh tools/opentopomap-render/scripts/otm-docker.sh`
- `docker compose -f tools/opentopomap-render/config/docker-compose.otm.yml config`
- `tools/opentopomap-render/scripts/plan-copernicus-dem.py alaska_z11`


## Alaska DEM Warp Overflow (2026-05-28)

The first server run of `/alaskarouter-scripts/prepare-copernicus-dem.sh` built
the Copernicus VRT and materialized a full Alaska 30m `raw.tif`, then failed in
`gdalwarp` with:

`ERROR 1: Integer overflow : nSrcXSize=92643, nSrcYSize=75600`

This is a GDAL 2.4/image-size limitation inside `jhassler/otm-docker`, not a
server capacity issue. Patched `prepare-copernicus-dem.sh` to keep `raw.vrt`
for inspection but feed the individual Copernicus COG files directly into each
`gdalwarp` command. That avoids one giant source raster while still emitting
the OpenTopoMap-required `warp-*`, `relief-*`, and `hillshade-*` products.

Validation:

- `bash -n tools/opentopomap-render/scripts/prepare-copernicus-dem.sh`
- `python3 -m unittest discover tools/opentopomap-render/tests`


## Alaska DEM Warp Progress (2026-05-28)

- Re-ran `prepare-copernicus-dem.sh` on `sol-icomp-03.lab.gdc.il.infinidat.com` under `/home/mlifshitz/tiles/AlaskaRouter` after removing stale warp outputs.
- The patched `gdalwarp` flow passed the previous GDAL 2.4 integer overflow by streaming the 596 Copernicus source COGs directly instead of materializing a giant `raw.tif` source.
- Current server outputs include `warp-30.tif` at roughly 46 GiB and `warp-60.tif` at roughly 13 GiB; `gdaldem hillshade` is still processing the 30 m derivative.
- Local validation remains `bash -n tools/opentopomap-render/scripts/prepare-copernicus-dem.sh` and `python3 -m unittest discover tools/opentopomap-render/tests`.


## Alaska Cropped DEM and Tiled Contours (2026-05-29)

- The first successful Alaska DEM rerun still produced an accidental full-world Mercator strip for `warp-60.tif` (`-180..+180`) because `gdalwarp` was not constrained to the target region extent. That made `phyghtmap` fail with memory errors.
- Added `DEM_TARGET_EXTENT` support to `prepare-copernicus-dem.sh` and reran the server prep with `DEM_TARGET_EXTENT="-180 51 -130 72"`. The corrected `warp-60.tif` is now `92662 x 85436` and bounded to `180W..130W`, `51N..72N`.
- Added an OTM helper patch step so the bundled peak/saddle C tools register all GDAL drivers and tolerate DEM-outside coordinates when using the VRT compatibility `raw.tif`.
- Added tiled Copernicus contour generation because full-region `phyghtmap` still exhausted memory during NumPy contouring. The tiled run uses 15000 px GeoTIFF chunks and emits normal `contour*.pbf` files for the upstream `06_dem_contours2.sh` import.

Validation:

- `bash -n tools/opentopomap-render/scripts/prepare-copernicus-dem.sh tools/opentopomap-render/scripts/patch-otm-dem-helpers.sh tools/opentopomap-render/scripts/prepare-copernicus-contours.sh tools/opentopomap-render/scripts/ensure-otm-deps.sh`
- `python3 -m unittest discover tools/opentopomap-render/tests`



## Alaska Chunked Contour Import (2026-05-30)

The first full Alaska contour import reached the upstream `06_dem_contours2.sh` step and failed in `osm2pgsql` 1.2 with `Segmentation fault (core dumped)` after a single process had parsed roughly 2.0B contour nodes. The generated contour PBFs themselves were present, but the all-at-once `contour*.pbf` import left `planet_osm_line` empty.

Added `scripts/import-contours-in-chunks.py` so Alaska imports one generated `contour-warp-60_*.pbf` per `osm2pgsql` process: first with `--create`, remaining files with `--append`. The helper records imported filenames under `/mnt/data/srtm/.contour-import-state/`, supports `--pattern` to exclude stale POC contour files, and supports `--flat-nodes` so the slim node store can live under `/mnt/db`.

Server run started under `/home/mlifshitz/tiles/AlaskaRouter/logs/import-contours-chunked.log` with 42 Alaska chunks, `--cache 32000`, and `/mnt/db/contours-flat-nodes.bin`. Early status: first two chunks imported, third chunk running; no segfault yet.



## Alaska Chunked Contour Import Failure (2026-05-30)

The detached chunked import did not complete. It imported 4 of 42 Alaska contour chunks, then failed on `contour-warp-60_1_5_lon-147.62_-139.53lat69.32_72.00_local-source.osm.pbf`. No `import-contours-in-chunks` or `osm2pgsql` process remained after the failure.

Observed error in `logs/import-contours-chunked.log`:

- `SQL command failed: ERROR: invalid memory alloc request size 1073741824`
- `DB copy thread failed: Executing SQL`
- `CalledProcessError` from the chunked helper while running `osm2pgsql --append ... contour-warp-60_1_5...pbf`

Diagnosis so far: the previous all-at-once crash was avoided, but the generated contour data is still too pathological for the old `osm2pgsql`/PostgreSQL path. The failure occurred while copying an enormous `planet_osm_ways` row containing a very large node-ref array with IDs around 4.01B. This points at the generated contour ways being too long / too dense for the importer, possibly amplified by the 1B tile ID stride and 10m contour interval. Next fix should reduce contour way complexity before import: regenerate contours with smaller tiles and/or less dense contour settings, and reconsider the ID allocation so generated IDs stay comfortably low while remaining unique.


## Alaska Failed-Tile Contour Proof (2026-05-30)

Confirmed the `invalid memory alloc request size 1073741824` was not a Docker
container RAM cap. PostgreSQL rejects single allocations around 1 GiB, and the
old 15000 px contour chunk could still produce importer input large enough to
hit that per-allocation limit even on a server with ample RAM.

Added a fail-fast contour validator and changed the Alaska contour generator
defaults to smaller, bounded contour files:

- `CONTOUR_TILE_SIZE=5000`
- `CONTOUR_MAX_NODES_PER_TILE=1000000`
- `CONTOUR_MAX_NODES_PER_WAY=2000`
- `CONTOUR_ID_STRIDE=5000000`
- `CONTOUR_OUTPUT_FORMAT=xml|pbf`

The XML mode exists for early failure on the current `jhassler/otm-docker`
image, which does not include `osmium`; XML can be scanned with Python alone.
Production can still generate PBF with the same bounds to keep disk usage and
import volume lower.

Server proof on `sol-icomp-03.lab.gdc.il.infinidat.com` under
`/home/mlifshitz/tiles/AlaskaRouter`:

- Retiled the previously failing source tile
  `/mnt/data/srtm/contour-tiles/warp-60_1_5.tif` into 9 separate 5000 px tiles.
- Generated XML contours for those 9 tiles with bounded nodes/ways and low ID
  stride.
- Validated all generated XML with
  `/alaskarouter-scripts/validate-contour-pbf.py --max-way-nodes 5000 --max-id 2000000000 --max-id-span 5000000`.
- Imported the validated XML proof into disposable database `contours_probe`
  with `import-contours-in-chunks.py --recreate --pattern '*.osm' --cache 8000`.
- Probe import completed without the PostgreSQL 1 GiB allocation failure.
  `planet_osm_line` now contains 63,825 rows and `planet_osm_ways` contains
  62,337 rows in `contours_probe`.

Next production step: sync the updated scripts to the server, generate a
bounded PBF contour set for the full Alaska `warp-60.tif`, then run the chunked
PBF import. If PBF import shows a new pathological file, rerun that local area
in XML validation mode before retrying.

Validation:

- `python3 -m unittest tools/opentopomap-render/tests/test_validate_contours.py tools/opentopomap-render/tests/test_import_contours.py`
- `python3 -m py_compile tools/opentopomap-render/scripts/validate-contour-pbf.py tools/opentopomap-render/scripts/import-contours-in-chunks.py`
- `bash -n tools/opentopomap-render/scripts/prepare-copernicus-contours.sh tools/opentopomap-render/scripts/otm-docker.sh`

## Alaska Batched Contour Import Plan (2026-05-30)

The one-PBF-per-osm2pgsql import proved stable but too slow, reaching roughly 337 chunks after several hours. Added a bounded batching mode to import-contours-in-chunks.py so we can resume from the existing marker file and reduce osm2pgsql startup overhead without recreating the contours database. Planned production resume: stop the current single-file importer only after preserving the marker state, then restart without --recreate using --batch-size 8 and --batch-max-bytes 250000000.

Validation:

- python3 -m unittest tools/opentopomap-render/tests/test_import_contours.py tools/opentopomap-render/tests/test_validate_contours.py
- python3 -m py_compile tools/opentopomap-render/scripts/import-contours-in-chunks.py

## Alaska Batched Import Handoff Correction (2026-05-30)

The first batched restart exposed a Python 3.6 compatibility bug: subprocess.run(text=True) is not available inside jhassler/otm-docker. Patch import-contours-in-chunks.py to use universal_newlines=True instead. Also remove the ambiguous handoff marker for contour-warp-60_05_09_lon-158.42_-155.72lat67.41_67.43_local-source.osm.pbf because the log did not show a full Osm2pgsql completion for that file after the old parent process was stopped; reimport it from the last unambiguous marker rather than risk silently omitting contours.

## Alaska z11 Render Started (2026-06-03)

The bounded production contour PBF import completed on sol-icomp-03.lab.gdc.il.infinidat.com under /home/mlifshitz/tiles/AlaskaRouter. The marker file reached 3167/3167 entries and the final import log granted Tirex SELECT access to the contours database. Cheap readiness checks confirmed both contours.planet_osm_line and gis.planet_osm_line return rows.

The first full tirex-batch enqueue after import failed because the Mapnik backend had not reloaded the opentopomap style, producing "map style opentopomap is not known" for 1225 metatile requests. Running tools/opentopomap-render/scripts/otm-docker.sh deps restarted tirex-backend-manager and tirex-master, after which a direct z11 test request rendered successfully with HTTP 200 and success=1 in /var/log/tirex/jobs.log.

Re-enqueued alaska_z11 with: tirex-batch -p 8 -d map=opentopomap bbox=-180.0,51.0,-130.0,72.0 z=11. Early status after the fixed enqueue: count_error=0, count_rendered[opentopomap][11]=280, queue size=941, four active renderers, and 281 z11 PNG files under /mnt/tiles/opentopomap/11. Next step is to let Tirex drain the queue, then export with export-region-tiles.py alaska_z11 and pack with pack-mbtiles.py.

## Alaska z11 Export and MBTiles Pack (2026-06-03)

The fixed Tirex render drained successfully on the server: 1225 alaska_z11 metatiles rendered, queue size reached 0, and no new render errors appeared after the 2026-06-03T07:30:58 renderer restart.

Export completed on sol-icomp-03.lab.gdc.il.infinidat.com under /home/mlifshitz/tiles/AlaskaRouter with tools/opentopomap-render/scripts/export-region-tiles.py alaska_z11 --force --jobs 16. Result: written=74955, skipped=0, failed=0.

Packing completed on the server with tools/opentopomap-render/scripts/pack-mbtiles.py. The generated artifact is tools/opentopomap-render/data/mbtiles/alaska_z11.mbtiles, 409 MiB, with 74955 rows in the tiles table and metadata minzoom=11/maxzoom=11/format=png.

During packing, the server Python 3.6 runtime exposed compatibility issues in export-region-tiles.py and pack-mbtiles.py. Updated those scripts locally and synced them to the server: removed postponed-annotation syntax from the exporter and made pack-mbtiles pass sqlite3.connect a string path. Added test_pack_mbtiles.py to cover MBTiles packing and the sqlite path compatibility.

Next step: transfer alaska_z11.mbtiles back from the server, convert it with local pmtiles convert, then merge the z11 PMTiles with the existing z0..10 Alaska pack. The first transfer attempt from the local machine failed with DNS resolution for sol-icomp-03.lab.gdc.il.infinidat.com returning -65563; retry when local DNS/connection recovers.

## Alaska z11 PMTiles Merge and App Install (2026-06-03)

The local transfer succeeded by forcing rsync to use ssh explicitly: rsync -az --partial --progress -e ssh. Converted the 409 MiB server MBTiles to tools/opentopomap-render/data/pmtiles/alaska_z11.pmtiles with pmtiles convert and verified it.

Merged the existing AlaskaRouter/Resources/alaska-pack.pmtiles z0..10 archive with the new z11-only PMTiles into tools/opentopomap-render/data/pmtiles/alaska-pack-z11-merged.pmtiles. pmtiles verify passed. The merged archive has header min zoom 0, max zoom 11, addressed tile count 101631, tile entries 60349, and tile contents 54095.

Updated the merged archive metadata maxzoom from 10 to 11 with pmtiles edit, then installed it as AlaskaRouter/Resources/alaska-pack.pmtiles. Updated AlaskaRouter/Resources/alaska-pack.manifest.json to version 2026-06-03, byte_size 868788161, Alaska coverage z6..11, Alaska tile_count 100266, and total_tile_count 101631.

Validation: pmtiles verify passed on the installed app pack, pmtiles show reports max zoom 11 and metadata maxzoom 11, pmtiles tile 11/160/672 returned a valid PNG, and a Fairbanks-area sample tile 11/183/535 returned a 20 KiB 8-bit PNG.

## Simulator Comparison, HD Zoom Cost, and Hillshade Plan (2026-06-03)

User validation in the iPhone Simulator against opentopomap.org confirmed that the z11 pack is a real improvement: the app gained roughly one to two additional plus-button zoom steps, the rendered cartography is close to public OpenTopoMap, and the app experience is stronger than the raw map because of POIs and search.

The remaining visual gap is terrain shading. Public OpenTopoMap has much stronger hillshade in mountainous areas; the app currently shows contours and water correctly but the relief is too flat. The first diagnostic target is the mountain area just west of Galbraith Lake Campground on the Dalton Highway, with additional checks around the Dalton corridor so the rendering pipeline is understood rather than tuned for one screenshot.

HD zoom cost estimate from the Alaska bbox [-180,51,-130,72] and measured z11 output: z11 rendered 74,955 PNG tiles and added about 381 MiB as PMTiles. Full-state z12 is 299,294 tiles, about 1.49 GiB additional; z13 is 1,194,900 tiles, about 5.93 GiB additional; z14 is 4,777,324 tiles, about 23.71 GiB additional. Cumulative z11..z12 is about 1.86 GiB, and z11..z13 is about 7.79 GiB. These are output-package estimates only; render/export temporary storage and network transfer need extra headroom.

Decision: fix hillshade before expanding bundled zoom. Statewide z12 may be technically possible but is probably too large for the v1 bundled package. For higher road-detail zooms, prefer region packages over zoom-level packages so the user downloads recognizable places such as Dalton/Fairbanks/Denali/Kenai detail rather than an abstract z13 layer. The v1 bundle target remains z0..z11 plus correct hillshade; an HD experiment can render one Dalton/Galbraith package at z12..z13 to measure size and value.

Current hillshade suspicion from server inspection: the OpenTopoMap XML includes hillshade layers, using /mnt/data/srtm/hillshade-30-jpeg.tif for z9..17 with grain-merge opacity 0.9. The high-resolution source exists, but the rendered result appears visually weak. Next work is to compare exact Dalton/Galbraith tiles against public OpenTopoMap, inspect/crop the hillshade raster for those tile bounds, and only then adjust the hillshade generation or style.

## Alaska Hillshade Root Cause (2026-06-03)

The z11 Alaska render used Alaska contour and OSM data but stale style-facing hillshade/relief rasters from the earlier Israel/Palestine proof run. gdalinfo on /mnt/data/srtm/warp-30.tif and warp-60.tif shows the Alaska bbox, but gdalinfo on /mnt/data/srtm/hillshade-30-jpeg.tif showed 33E..36E and 29N..34N. That explains the flat Dalton/Galbraith render: Mapnik had no hillshade coverage for Alaska.

A Galbraith Lake Campground diagnostic used approximate z11 tile 173/482, bbox lon -149.58984375..-149.4140625 and lat 68.46379955520322..68.52823492039876. The installed app tile is 12 KiB and visually flat; the matching public OpenTopoMap tile is 20 KiB and has visible gray terrain relief. A crop from Alaska warp-30.tif rendered with gdaldem hillshade -z 2 shows healthy soft terrain, while z5/z7 are stronger but harsher. Therefore the immediate fix is to regenerate Alaska hillshade outputs from the existing Alaska warps, not to redownload DEM data or change the z factor first.

Updated prepare-copernicus-dem.sh to support DEM_DERIVATIVES_ONLY=1 so existing warp-5000/1000/500/30 rasters can regenerate relief and hillshade without repeating the expensive Alaska warps. The script now writes derivative GeoTIFFs to temporary names and publishes them with mv, preventing a half-written style-facing hillshade file during long jobs. The high-zoom hillshade now writes hillshade-30-jpeg.tif directly as a tiled JPEG GeoTIFF to avoid the large hillshade-30.tif intermediate.

Started the server regeneration on sol-icomp-03.lab.gdc.il.infinidat.com under /home/mlifshitz/tiles/AlaskaRouter with DEM_DERIVATIVES_ONLY=1, logging to logs/prepare-alaska-shading.log. It completed the low-resolution derivatives and is currently running gdaldem hillshade -z 2 against /mnt/data/srtm/warp-30.tif, writing /mnt/data/srtm/hillshade-30-jpeg.tmp.tif. When that finishes, verify gdalinfo shows Alaska coverage, render the Galbraith z11 sample, then rerender/export/repack Alaska z11.

## Alaska Hillshade Regeneration Completed (2026-06-03)

DEM derivative regeneration finished successfully. /mnt/data/srtm/hillshade-30-jpeg.tif is now a 1015 MiB tiled JPEG GeoTIFF with gdalinfo coverage over Alaska: upper-left 180W/72N, lower-right about 130W/51N, center about 155W/63.35N. The stale Israel/Palestine hillshade is no longer the style-facing high-zoom raster.

Restarted Tirex/Mapnik so the renderer reopened the corrected raster. A targeted live render of Galbraith metatile z11 x=168 y=480 completed, increasing Tirex rendered count from 1225 to 1226. The sample tile 11/173/482 changed from the old flat 12 KiB PNG, sha256 186de497ac250bbdcce3185c4bd964f27d4981d8a3ed3622adb3225547dbd03a, to a corrected 20 KiB PNG, sha256 ada28d4e9b56b29f4a109e2d07dda5135b947e10c690b986165654f813a69444. This matches the public OpenTopoMap tile size class and confirms hillshade is now participating in the render.

Next step started from this checkpoint: rerender all Alaska z11 metatiles with the corrected hillshade, then export, pack MBTiles, convert/merge PMTiles, and reinstall the app package.

## Corrected Alaska z11 Pack Installed (2026-06-03)

The corrected Alaska z11 rerender completed cleanly. Tirex jobs.log showed 2451 successful z11 metatile renders and 0 failed renders, with the final render around 2026-06-03T10:45:06Z. Forced export completed with written=74955, skipped=0, failed=0.

Packed the corrected export into tools/opentopomap-render/data/mbtiles/alaska_z11.mbtiles on the server. The hillshaded MBTiles is 686 MiB, up from the previous 409 MiB unshaded/flat z11 pack. Transferred it locally, converted it to tools/opentopomap-render/data/pmtiles/alaska_z11.pmtiles, and verified the archive. Corrected z11 PMTiles is 655 MiB.

Extracted the existing installed app pack to z0..10 to avoid stale z11 collisions, then merged that z0..10 archive with the corrected z11 PMTiles. The merged archive verified successfully and is installed as AlaskaRouter/Resources/alaska-pack.pmtiles. The installed pack is 1155303077 bytes, has maxzoom 11, addressed tile count 101631, tile entries 63847, and tile contents 58812.

Validation: pmtiles verify passed on the installed app pack; pmtiles show reports header and metadata maxzoom 11; pmtiles tile AlaskaRouter/Resources/alaska-pack.pmtiles 11 173 482 returns a 20 KiB PNG with sha256 ada28d4e9b56b29f4a109e2d07dda5135b947e10c690b986165654f813a69444, matching the corrected Galbraith render.

## Status 2026-06-07: production z11 delivered
The self-render pipeline is fully working and has shipped statewide Alaska z=11 (corrected EPSG:3857 hillshade + geographic contours) into the app pack. The ORIGINAL goal of this bean — applying political-label overrides (Israel low-zoom, Falklands/Malvinas) at render time — was never implemented; only the pipeline + Alaska detail production. Consider splitting the label-override work into its own v2 bean and closing this one as 'pipeline delivered'.
