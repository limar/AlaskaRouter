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
- `pack-mbtiles.py`: convert a rendered `z/x/y.png` tile tree into MBTiles.

The Mapnik/OpenTopoMap renderer itself is the next slice. It should write PNGs
into `tools/opentopomap-render/data/tiles/<region>/<z>/<x>/<y>.png`, after
which `pack-mbtiles.py` and `pmtiles convert` can package them.

## Scratch Paths

All generated data lives under `tools/opentopomap-render/data/`, which is
gitignored.
