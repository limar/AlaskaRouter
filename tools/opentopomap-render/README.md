# OpenTopoMap Self-Render Pipeline

This workspace supports `AlaskaRouter-6ihk`: render OpenTopoMap-compatible
raster tiles ourselves instead of bulk-downloading public tile-server PNGs.

The immediate v1 driver is `AlaskaRouter-2ptw`: add statewide Alaska z=11
detail. The preferred flow is now:

1. Render only the Alaska z=11 delta from OSM/SRTM source data.
2. Convert rendered PNG tiles to MBTiles/PMTiles.
3. Merge the z=11 PMTiles with the existing z=0..10 `alaska-pack.pmtiles`.
4. Publish the replacement pack through the existing GitHub Releases flow.

Runtime package infrastructure remains deferred.

## Disk And Bandwidth

Local workspace check on 2026-05-28: 185 GiB free. That is enough for the
Alaska z=11 delta and conversion scratch, but full self-rendering also needs
server-side space for:

- Geofabrik Alaska PBF: hundreds of MB compressed.
- PostGIS import: multiple GB, HDD-friendly but slow.
- SRTM/hillshade cache: region subset preferred, not global.
- Rendered z=11 PNG tile tree: roughly 75k tiles.
- MBTiles + PMTiles + merged final pack.

Network should be used for source datasets intended for bulk use:
Geofabrik PBFs, SRTM sources, and final GitHub Release assets. Do not use
public tile servers as the source for offline archive creation unless the
operator explicitly permits it.

## Region Config

`config/regions.json` defines named render targets. Start with:

```bash
tools/opentopomap-render/scripts/estimate-region.py alaska_z11
```

Expected Alaska z=11 target count: 74,955 tiles.

## Current Script Surface

- `estimate-region.py`: deterministic tile-count / bbox math.
- `fetch-osm.sh`: resumable Geofabrik PBF fetch plus sidecar checksum fetch.
- `prepare-otm-docker.sh`: lays out a configured region as `osmdata.pbf` for
  the Docker image.
- `otm-docker.sh`: wraps the compose file for start/stop/logs/shell.
- `render-region-command.py`: prints the `tirex-batch` command for a region.
- `export-region-tiles.py`: copies rendered PNGs from the local renderer into
  the packageable `z/x/y.png` tree.
- `pack-mbtiles.py`: convert a rendered `z/x/y.png` tile tree into MBTiles.

The Docker renderer and exporter now write PNGs into
`tools/opentopomap-render/data/tiles/<region>/<z>/<x>/<y>.png`, after which
`pack-mbtiles.py` and `pmtiles convert` can package them.

## Docker Renderer Bootstrap

The official OpenTopoMap repository contains the Mapnik renderer files, and
the `lukey78/otm-docker` wrapper packages those files into a Docker setup. Its
README expects:

- `data/data/osmdata.pbf`
- `data/data/srtm/`
- `data/db`
- `data/letsencrypt`

Our wrapper maps those paths under `tools/opentopomap-render/data/docker/`.

```bash
# 1. Estimate the target.
tools/opentopomap-render/scripts/estimate-region.py israel_palestine_poc

# 2. Fetch the configured Geofabrik extract.
tools/opentopomap-render/scripts/fetch-osm.sh israel_palestine_poc

# 3. Prepare the Docker data layout.
tools/opentopomap-render/scripts/prepare-otm-docker.sh israel_palestine_poc

# 4. Add region-covering SRTM ZIP/HGT files to:
#    tools/opentopomap-render/data/docker/data/srtm/

# 5. Start the container and run the one-time import scripts.
tools/opentopomap-render/scripts/otm-docker.sh up
tools/opentopomap-render/scripts/otm-docker.sh scripts
tools/opentopomap-render/scripts/otm-docker.sh shell

# 6. Print the pre-render command for the region.
tools/opentopomap-render/scripts/render-region-command.py israel_palestine_poc

# 7. Export rendered tiles from the local HTTP renderer into the packable tree.
tools/opentopomap-render/scripts/export-region-tiles.py israel_palestine_poc
```

The exporter is resumable by default: existing PNG files are skipped unless
`--force` is passed. Use `--dry-run` before a large export:

```bash
tools/opentopomap-render/scripts/export-region-tiles.py alaska_z11 --dry-run
```

## Scratch Paths

All generated data lives under `tools/opentopomap-render/data/`, which is
gitignored.
