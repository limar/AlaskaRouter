# Rendering kitchen — traps we already hit

Hard-won failure modes from building this pipeline. If a render looks wrong or a
stage crashes, check here first.

## Contours

**Brown contours render as spidernets / tangled lines in part of the map.**
osm2pgsql **1.2.0** (in the upstream render image) mishandles node ids above
**~2³² (4.29 B)** when building way geometry from flat-nodes — high-id tiles get
ways wired to the wrong nodes. Our per-tile id stride pushed statewide ids to
~18 B, so the southern/high-id half spidernetted. **Fix:** import with the
**osm2pgsql 1.11 sidecar** (`make import`), which handles 64-bit ids natively.
Don't import contours with the in-container 1.2.0.

**Contours collapse into a dense horizontal band, empty above/below.** Contours
were generated from a **projected** (Mercator) DEM. `phyghtmap` expects a
**geographic** (EPSG:4326) DEM; the Mercator latitude axis distorts. `warp-60`
(the contour source) must be EPSG:4326 — that's what `prepare-copernicus-dem.sh`
builds (`CONTOUR_SRC_DEG`).

**osm2pgsql 1.11 segfaults at startup during import.** Two separate cliffs:
(1) a single `--create` with **~400+ input files** crashes at setup; (2) the
**`--append`** path (legacy pgsql output) also segfaults. So neither one-shot-many
nor batched import works. `import-contours-sidecar.sh` works around both by
`osmium sort`-ing all per-tile PBFs into **one ordered file** → a single
`--create`. (osmium sort also satisfies osm2pgsql's "nodes before ways" ordering;
plain `osmium cat` does not.)

**`-P` did something weird.** In osm2pgsql, `-P` is the **database port**, not the
process count. Use `--number-processes`.

## Hillshade / DEM

**Hillshade shifted ~SE relative to roads/contours.** The DEM was warped to the
wrong Mercator sphere. Do **not** write `+proj=merc +ellps=sphere +R=6378137`:
PROJ honors `+ellps=sphere` (radius 6370997) and drops `+R`. Use
`-t_srs EPSG:3857` (a=6378137), which is what the OTM Mapnik style assumes and
places **without** reprojection.

**A region shows another region's terrain / flat relief.** The style-facing
rasters in `/mnt/data/srtm/` are **shared across regions** with no isolation (we
once shipped Israel's hillshade in Alaska). Regenerate the derivatives for the
current region and sanity-check with `gdalinfo <raster> | grep "Upper Left"`.

**`gdalwarp ... *.tif` errors "No such file or directory".** A `*.tif` glob in a
`docker exec` expands on the **host**, not in the container. Wrap it:
`docker exec C sh -c 'gdalwarp ... /mnt/data/copernicus-dem/*.tif ...'`.

## Container / render

**PostgreSQL won't start after `docker compose down/up` (container recreate).**
The image ships only `postgresql.conf` in `/etc/postgresql/10/main`;
`pg_hba.conf`, `pg_ident.conf`, `conf.d/`, `start.conf` are created at first run
in the **ephemeral** layer and lost on recreate. **The data is safe** (on the
`data/docker/db` + `data/docker/tablespace` bind mounts). Recovery: start the
container, recreate those files (localhost/socket `trust` is fine — PG isn't
published), `chown -R postgres:postgres`, then `make deps`. Avoid recreating the
container needlessly; baking this in is **AlaskaRouter-msgi**.

**Blank tiles / Tirex `map style opentopomap is not known`.** After any DB or
raster change, the Mapnik backend must reload: `make deps` (restarts
tirex-backend-manager + tirex-master and re-creates the tile-cache dirs).

**A driver log says `mbtiles=26M` but the file is 738 M.** The `du` in the driver
runs before the SQLite file is fully flushed — trust `ls -lah` on the actual
file, and sanity-check `SELECT avg(length(tile_data)) FROM tiles` (blank ≈ tens
of bytes; real ≈ 10 KB).

## Performance

The contour import is HDD-IO-bound. The sidecar keeps the flat-nodes on a
**tmpfs** (RAM) and uses `--cache 0` so node lookups stay in RAM — that's the big
win on this HDD server. Further levers (PostgreSQL import tuning, ZFS
`sync=disabled`) are in **AlaskaRouter-0bq8**.
