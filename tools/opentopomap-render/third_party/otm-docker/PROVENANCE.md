# Vendored third-party source — `otm-docker`

This directory is a **verbatim snapshot of someone else's work**, kept so our
render kitchen survives the upstream image being removed from Docker Hub. It is
**not ours** and is **not shipped in the app** — it is build-time tooling.

## Source & attribution
- **Upstream:** https://github.com/lukey78/otm-docker — *"Docker image for
  Opentopomap tile server"* by **lukey78**.
- **Snapshotted commit:** `a024111e0d7302da3f784c4b0ce3697a38900935`
- **Fetched:** 2026-06-10
- The Docker Hub image we currently run (`jhassler/otm-docker`) is this repo
  published by **jhassler**.
- The cartography in `assets/home/otm/` (the `opentopomap.xml` style, the
  `styles-otm/` modules, the `symbols-otm/` icons, `relief_color_text_file.txt`)
  originates from **der-stefan / OpenTopoMap**
  (https://github.com/der-stefan/OpenTopoMap), *"A topographic map from
  OpenStreetMap and SRTM data."*

## Licensing — READ BEFORE ANY PUBLIC / OSS / APP-STORE RELEASE
We are **not lawyers**; this records what we know, not legal advice.

- **`lukey78/otm-docker`: NO license** (GitHub `license: null`) → default
  **all rights reserved**. We have **no explicit permission to redistribute it**.
  It is vendored here for our **own private build use / reproducibility**.
- **`der-stefan/OpenTopoMap`:** license is **"Other / NOASSERTION"** — must be
  read directly; not a standard OSI/SPDX license.
- Bundled tools (Mapnik, Tirex, mod_tile, osm2pgsql): GPL/LGPL.
- The **rendered tiles** we actually ship derive from **OpenStreetMap (ODbL)**
  + the **OpenTopoMap style (CC-BY-SA)** — attribution required, ShareAlike on
  the tiles. The app must show OSM + OpenTopoMap credits.

**Before this repository is made public or the app is submitted with this as a
dependency:** clear the license — ask lukey78 for permission/a license, and/or
re-derive our own image from der-stefan/OpenTopoMap after reading its terms,
rather than republishing this no-license snapshot. Tracked in a bean.

## Why vendored (not just referenced)
The upstream image could vanish from Docker Hub, and this small repo (~1.9 MB)
also carries the OTM **cartography + import scripts** we want to own and modify
(e.g. the vibrant-high-zoom relief work). Keeping the source is cheaper and more
useful than archiving the 2 GB built image.

## Rebuild caveats — the Dockerfile here will NOT build as-is today
If we ever must rebuild the base from this source, it needs modernizing:
- `FROM ubuntu` is **unpinned** → today resolves to 24.04, not the 18.04 the
  working image was built on. Pin `ubuntu:18.04`.
- `git clone git://github.com/...` — GitHub **removed the `git://` protocol**
  (2022); change to `https://`.
- It builds **osm2pgsql from `master`** → now 2.x, which **dropped the legacy
  `--output=pgsql`** the OTM import scripts rely on. Pin a 1.x tag. (This is the
  same version trap we solved at import time with the osm2pgsql 1.11 sidecar.)
- `certbot-auto` was **retired (2021)** — drop or replace it.
- **phyghtmap** is fetched from a personal server (`katze.tfiu.de`) as a
  `.deb`. Don't. That host is now serving a bad TLS cert and the original tool
  is unmaintained. The `.deb` was `_all` (pure Python) anyway — never needed to
  be a binary. Instead `pip install pyhgtmap` — the maintained Python-3 fork
  (https://github.com/agrenott/pyhgtmap, on PyPI, command `pyhgtmap`). Pin a
  version. Note: our `scripts/prepare-copernicus-contours.sh` invokes the
  command name **`phyghtmap`** (provided today by the base image). A rebuild on
  `pyhgtmap` needs either a `phyghtmap`→`pyhgtmap` shim/alias or a one-word
  change to that script. (We do NOT vendor the binary — build on demand.)

## What we actually run
We don't build from this directory today. We run a thin image
(`../../docker/otm-render/Dockerfile`) **`FROM` the digest-pinned** published
image. This snapshot is the fallback blueprint + the cartography asset source.
