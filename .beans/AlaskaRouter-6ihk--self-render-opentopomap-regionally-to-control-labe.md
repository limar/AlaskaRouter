---
# AlaskaRouter-6ihk
title: Self-render OpenTopoMap regionally to control labels at render time
status: todo
type: feature
priority: high
created_at: 2026-05-23T19:29:19Z
updated_at: 2026-05-31T14:13:44Z
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
