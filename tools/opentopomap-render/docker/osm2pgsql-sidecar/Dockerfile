# Modern osm2pgsql importer sidecar (AlaskaRouter-msgi).
# The OTM render image (jhassler/otm-docker, Ubuntu 18.04) is pinned to
# osm2pgsql 1.2.0, which corrupts way geometry for node ids > ~2^32 (the
# statewide-contour spidernet bug, AlaskaRouter-6fop). osm2pgsql and Mapnik are
# independent stages, so we run imports from this modern sidecar against the
# SAME PostGIS, leaving the proven render stack untouched.
#
# ubuntu:24.04 ships osm2pgsql 1.11 (apt): keeps --output=pgsql (1.x, so the OTM
# planet_osm_* schema is unchanged), native 64-bit ids, much faster, supports
# --number-processes. It joins the render container's network namespace
# (docker run --network container:alaskarouter-otm) to reach PG on 127.0.0.1 --
# no PostgreSQL listen_addresses change, no extra network exposure.
# osmium-tool: merge the many per-tile contour PBFs into one file before import.
# osm2pgsql 1.11 segfaults on a single --create with ~400+ input files, AND its
# --append path (legacy pgsql output) segfaults too -- so neither one-shot-many
# nor batched import works. Merging to one file -> one --create sidesteps both.
FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      osm2pgsql osmium-tool python3 postgresql-client ca-certificates \
 && rm -rf /var/lib/apt/lists/*
