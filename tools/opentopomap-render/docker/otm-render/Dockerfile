# AlaskaRouter render image (AlaskaRouter-msgi).
#
# A thin layer over the upstream OpenTopoMap stack, PINNED BY DIGEST so every
# bootstrap gets the identical render stack (the :latest tag is mutable). We
# can't rebuild the base from source (Mapnik/Tirex/OTM on Ubuntu 18.04 is exactly
# what the prebuilt image spares us) -- for independence from Docker Hub,
# `docker save` this built image to a tarball we archive (see BOOTSTRAP.md).
#
# What we bake (so `docker compose down/up` no longer breaks the container):
#  - A COMPLETE /etc/postgresql/10/main config. The base ships only
#    postgresql.conf; pg_hba/pg_ident/conf.d/start.conf are created at first run
#    in the ephemeral layer and lost on recreate -> PostgreSQL won't boot.
#  - python-gdal: the legacy gdal_fillnodata.py / gdal_merge.py helpers the DEM
#    step needs (otherwise installed at runtime by ensure-otm-deps).
#
# Build:  docker build -t alaskarouter/otm-render:2026-06-10 docker/otm-render
# (the Makefile/compose reference this image; `make sidecar-image` builds the
#  separate importer image.)
FROM jhassler/otm-docker@sha256:adbe421f654c198d58b400af5449ec3a784af081e22ba1ad897383a8dab1997b

RUN apt-get update \
 && apt-get install -y --no-install-recommends python-gdal \
 && rm -rf /var/lib/apt/lists/*

COPY etc/postgresql/10/main/ /etc/postgresql/10/main/
RUN rm -f /etc/postgresql/10/main/conf.d/README \
 && chown -R postgres:postgres /etc/postgresql/10/main \
 && chmod 750 /etc/postgresql/10/main/conf.d \
 && chmod 640 /etc/postgresql/10/main/pg_hba.conf /etc/postgresql/10/main/pg_ident.conf
