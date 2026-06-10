# Bootstrap the rendering kitchen from zero

Goal: from **only git** (new laptop, new render server, no memory of prior
sessions) get to a rendered, installed map pack. Two machines:

| Machine | Role | Tools |
|---|---|---|
| **Render server** (Linux, lots of RAM/CPU/disk, Docker) | the heavy lifting: OSM/DEM import, contours, Mapnik render, export, pack | docker, make, python3 |
| **Laptop** (this repo's dev box) | drives the server, packages + installs + publishes the pack, builds the app | git, gh, jq, pmtiles, rsync, ImageMagick, python3 |

The render pipeline is a **Makefile** (`tools/opentopomap-render/Makefile`) run on
the server. The laptop deploys the code, then pulls the result and packages it.
Architecture + war stories: `docs/RUNBOOK.md`. Gotchas: `docs/TROUBLESHOOTING.md`.

---

## 0. Prerequisites

**Laptop:** `git`, `gh` (auth'd: `gh auth status`), `jq`, `pmtiles`
(`brew install pmtiles`), `rsync`, `imagemagick`, `python3`.

**Server:** Docker (`docker --version`), `make`, `python3`, and enough disk for a
region (Alaska: COGs ~60 GB, warp-30 ~46 GB, contours a few GB, flat-nodes on
tmpfs ~RAM; budget ~250 GB scratch). RAM matters: the contour import keeps its
node store in a tmpfs (RAM) -- see RUNBOOK.

---

## 1. Get the code onto the server

The server usually has **no GitHub credentials**, so push a git **bundle** from
the laptop rather than cloning:

```bash
# laptop
git bundle create /tmp/repo.bundle master
scp /tmp/repo.bundle SERVER:~/repo.bundle
# server (first time)
mkdir -p ~/tiles/AlaskaRouter && cd ~/tiles/AlaskaRouter
git init -q && git fetch -q ~/repo.bundle 'refs/heads/master:refs/heads/master'
git checkout -f master
# updates later: re-bundle, then `git fetch <bundle> ...:refs/remotes/b/master && git reset --hard refs/remotes/b/master`
```

Render scratch (`tools/opentopomap-render/data/`) is gitignored and stays on the
server across updates.

---

## 2. Build the images + stand up the container (one-time)

We run a **thin image over the upstream OpenTopoMap stack pinned by digest**
(`docker/otm-render/Dockerfile`) that bakes the `/etc/postgresql` config +
`python-gdal`, so a container recreate no longer breaks PostgreSQL. Plus the
modern osm2pgsql importer sidecar.

```bash
cd ~/tiles/AlaskaRouter/tools/opentopomap-render
make images          # build alaskarouter/otm-render + the osm2pgsql sidecar
#   ...or, if Docker Hub no longer has the base, load the archived tarballs:
#   make load-images   (expects data/images/*.tar.gz -- see `make save-images`)

bash scripts/prepare-otm-docker.sh <REGION>      # wire the data layout
docker compose -f config/docker-compose.otm.yml up -d
# First run only: run the OTM import scripts INSIDE the container, in order:
#   00_setup_database 01_download_water_polys 02_import_osm_data 04_preprocess_osm_data
#   (03/05/06 are DEM/contours -- replaced by our `make dem`/`contours` below)
make deps             # tile dirs + Tirex restart (idempotent)
make style            # our style patches: relief to z11, no contours (idempotent)
```

> Tiles are served on the host at `127.0.0.1:8088` (localhost-only). The importer
> sidecar reaches PostgreSQL over the container's network namespace -- no extra
> exposure. PG data lives on the `data/docker/db` + `data/docker/tablespace` bind
> mounts and survives a recreate; with the baked image, PG also boots cleanly
> after one. To keep the kitchen independent of Docker Hub, archive the images
> once with `make save-images` (and optionally publish the tarballs).

---

## 3. Render a region (the Makefile)

Define the region once in `config/regions.json` (bbox, zooms, Geofabrik URL),
then:

```bash
cd ~/tiles/AlaskaRouter/tools/opentopomap-render
make help                                  # list stages
make fetch         REGION=alaska_z11        # OSM PBF + Copernicus DEM
make render-region REGION=alaska_z11        # dem -> contours -> import -> render -> export -> pack
# or run stages individually: make dem / contours / import / render / export / pack
```

Result: `data/mbtiles/<REGION>.mbtiles`. Knobs: `CONTOUR_SRC_DEG` (contour DEM
resolution, default 0.001=~90 m; hillshade is independent), `RENDER_PROCS`,
`FLAT_TMPFS`.

---

## 4. Finish on the laptop (package + install + publish)

`<REGION>` here is `alaska_z11`; adjust the merge for the pack's zoom layout.

```bash
# laptop
cd <repo>
R=tools/opentopomap-render/data
R2=$R/pmtiles; mkdir -p $R2
# pull the rendered mbtiles (verify checksum vs the server)
rsync -az --partial -e ssh SERVER:'~/tiles/AlaskaRouter/'$R'/mbtiles/alaska_z11.mbtiles' $R/mbtiles/alaska_z11.mbtiles
# convert + merge with the unchanged z0-10, install into the app bundle
pmtiles convert $R/mbtiles/alaska_z11.mbtiles $R2/alaska_z11.pmtiles
pmtiles extract AlaskaRouter/Resources/alaska-pack.pmtiles $R2/alaska_z0-10.pmtiles --maxzoom=10
pmtiles merge   $R2/alaska_z0-10.pmtiles $R2/alaska_z11.pmtiles $R2/merged.pmtiles
cp $R2/merged.pmtiles AlaskaRouter/Resources/alaska-pack.pmtiles
pmtiles verify AlaskaRouter/Resources/alaska-pack.pmtiles
# bump AlaskaRouter/Resources/alaska-pack.manifest.json (version/byte_size/built_at/render_commit), then:
tools/build-pack/release-pack.sh           # publish as a GitHub Release (data/alaska-<version>)
```

A fresh clone gets the (gitignored) pack back with
`tools/build-pack/fetch-pack.sh`.

> TODO (AlaskaRouter-iobu): wrap section 4 in a laptop-side `make install-pack` /
> `make publish` so this stops being copy-paste too.

---

## What's still manual / fragile (tracked)

- Container first-run + recreate-safety is hand-done -> **AlaskaRouter-msgi**
  (pin the image by digest + bake the config/deps).
- Section 4 (laptop packaging) is not yet a Makefile -> **AlaskaRouter-iobu**.
- See `docs/TROUBLESHOOTING.md` for the osm2pgsql/PostgreSQL traps we already hit.
