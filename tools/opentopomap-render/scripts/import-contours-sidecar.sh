#!/bin/bash
# Import generated contour PBFs via the modern osm2pgsql 1.11 sidecar
# (AlaskaRouter-msgi). Runs INSIDE the sidecar container; connects to the render
# container's PostgreSQL over TCP using PGHOST/PGPORT/PGUSER from the
# environment (the caller sets them via `docker run -e ...`).
#
# Replaces the osm2pgsql-1.2.0 chunked import (import-contours-in-chunks.py):
# 1.11 handles 64-bit node ids natively (fixes the >2^32 spidernet, 6fop) and
# imports all PBFs in one parallel pass. flat-nodes lives on a tmpfs mount
# (caller: `docker run --tmpfs /flat:size=...`) so node lookups stay in RAM,
# which is what makes the HDD-backed import fast (AlaskaRouter-0bq8).
#
# Typical invocation (from the render host):
#   docker run --rm --network container:alaskarouter-otm \
#     -e PGHOST=127.0.0.1 -e PGPORT=5432 -e PGUSER=postgres \
#     --tmpfs /flat:size=170g \
#     -v <data>/docker/data:/mnt/data \
#     -v <repo>/tools/opentopomap-render/scripts:/alaskarouter-scripts \
#     alaskarouter/osm2pgsql:1.11 \
#     bash /alaskarouter-scripts/import-contours-sidecar.sh 'contours-sw2/contour-warp-60_*.pbf'
#
# Stop the render backend first so it releases connections to the contours DB:
#   docker exec alaskarouter-otm bash -lc 'service tirex-backend-manager stop; service tirex-master stop'
# and restart it afterwards with otm-docker.sh deps.
set -euo pipefail

SRTM_DIR="${SRTM_DIR:-/mnt/data/srtm}"
PATTERN="${1:-contours-sw2/contour-warp-60_*.pbf}"
DB="${CONTOURS_DB:-contours}"
STYLE="${CONTOUR_STYLE:-/mnt/data/contours.style}"
JOBS="${OSM2PGSQL_PROCESSES:-8}"
FLAT="${FLAT_NODES:-/flat/nodes.bin}"

cd "${SRTM_DIR}"
# shellcheck disable=SC2086
files=$(ls ${PATTERN} 2>/dev/null || true)
[ -n "${files}" ] || { echo "No contour PBFs match ${SRTM_DIR}/${PATTERN}" >&2; exit 1; }
echo "Importing $(echo "${files}" | wc -w) contour PBFs into '${DB}' with $(osm2pgsql --version 2>&1 | head -1)"

# Recreate the contours DB (drop needs no other connections -> stop tirex first).
psql -d postgres -tAc "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB}'" >/dev/null 2>&1 || true
dropdb --if-exists "${DB}"
createdb "${DB}" -O tirex
psql -d "${DB}" -c "CREATE EXTENSION IF NOT EXISTS postgis;" >/dev/null

# Batch the inputs: osm2pgsql 1.11 segfaults at startup when handed too many
# input files in one invocation (verified on the coarse set: 100 files OK, ~400+
# crash at setup regardless of --number-processes or nofile ulimit). Import in
# batches of 100 -- first batch --create, the rest --append into the shared
# --flat-nodes. Postprocessing is ~0s for line-only contour data, so the
# per-batch overhead is negligible. --cache 0: rely on the tmpfs flat-nodes
# (RAM) + ZFS ARC. NOTE: osm2pgsql -P is PORT; process count is --number-processes.
BATCH="${OSM2PGSQL_BATCH:-100}"
tmpd="$(mktemp -d)"
trap 'rm -rf "${tmpd}"' EXIT
printf '%s\n' ${files} | split -l "${BATCH}" - "${tmpd}/b_"
mode="--create"
for b in "${tmpd}"/b_*; do
  echo "  batch $(basename "${b}"): $(wc -l < "${b}") files (${mode})"
  # shellcheck disable=SC2046,SC2086
  osm2pgsql ${mode} --slim --output=pgsql -d "${DB}" \
    --cache 0 --number-processes "${JOBS}" \
    --style "${STYLE}" --flat-nodes "${FLAT}" \
    $(cat "${b}")
  mode="--append"
done

psql -d "${DB}" -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO tirex;" >/dev/null
echo "Contour import complete: $(psql -d "${DB}" -XtAc "SELECT count(*) FROM planet_osm_line") lines"
