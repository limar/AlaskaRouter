#!/usr/bin/env bash
# Generate contour files from a large Copernicus-derived warp-60.tif in chunks.
#
# warp-60.tif MUST be a GEOGRAPHIC (EPSG:4326) DEM, as produced by
# prepare-copernicus-dem.sh. phyghtmap is built for geographic input and reads
# the raster's CRS automatically; feeding it a projected Mercator raster distorts
# latitudes into dense/empty contour bands (AlaskaRouter-6fop). Do not "optimize"
# this to consume a Mercator warp.

set -euo pipefail

SRTM_DIR="${1:-/mnt/data/srtm}"
TILE_SIZE="${CONTOUR_TILE_SIZE:-5000}"
JOBS="${CONTOUR_JOBS:-1}"
ID_START="${CONTOUR_ID_START:-10000000}"
# Each source tile gets a disjoint node/way ID range [ID_START + i*ID_STRIDE, ...).
# ID_STRIDE MUST exceed the node count of the densest source tile, or its IDs spill
# into the next tile's range and osm2pgsql --append overwrites those nodes, wiring
# ways to wrong positions (spidernet/displaced contours — AlaskaRouter-6fop). The
# bounded Galbraith POC hid this because it had a single tile. Measured statewide
# max was 47.2M nodes/tile (5000px @ 0.0005deg, -s 10), so 100M gives ~2x headroom.
# Larger CONTOUR_TILE_SIZE => more nodes/tile => raise this too. Max node id ends up
# ~= ID_START + n_tiles*ID_STRIDE, which sizes the osm2pgsql --flat-nodes file
# (8 bytes/id): 180 tiles * 100M -> ~143 GB flat-nodes, fine on this server.
ID_STRIDE="${CONTOUR_ID_STRIDE:-100000000}"
MAX_NODES_PER_TILE="${CONTOUR_MAX_NODES_PER_TILE:-1000000}"
MAX_NODES_PER_WAY="${CONTOUR_MAX_NODES_PER_WAY:-2000}"
TILE_DIR="${CONTOUR_TILE_DIR:-contour-tiles-${TILE_SIZE}}"
OUTPUT_DIR="${CONTOUR_OUTPUT_DIR:-contours-${TILE_SIZE}}"
OUTPUT_FORMAT="${CONTOUR_OUTPUT_FORMAT:-pbf}"
# Contour generator binary. Defaults to `phyghtmap` (the command the OTM base
# image provides). A from-scratch rebuild installs the maintained py3 fork
# `pyhgtmap` (pip, https://github.com/agrenott/pyhgtmap) -- point at it with
# PHYGHTMAP_BIN=pyhgtmap, no script edit. See third_party/otm-docker/PROVENANCE.md.
PHYGHTMAP_BIN="${PHYGHTMAP_BIN:-phyghtmap}"

case "${OUTPUT_FORMAT}" in
  pbf|xml)
    ;;
  *)
    echo "CONTOUR_OUTPUT_FORMAT must be pbf or xml, got ${OUTPUT_FORMAT}" >&2
    exit 2
    ;;
esac

OUTPUT_EXTENSION="pbf"
if [[ "${OUTPUT_FORMAT}" == "xml" ]]; then
  OUTPUT_EXTENSION="osm"
fi

export ID_START ID_STRIDE MAX_NODES_PER_TILE MAX_NODES_PER_WAY OUTPUT_DIR OUTPUT_FORMAT PHYGHTMAP_BIN

cd "${SRTM_DIR}"

if [[ ! -f warp-60.tif ]]; then
  echo "Missing ${SRTM_DIR}/warp-60.tif" >&2
  exit 1
fi

mkdir -p "${TILE_DIR}" "${OUTPUT_DIR}"

if ! find "${TILE_DIR}" -maxdepth 1 -name '*.tif' -print -quit | grep -q .; then
  gdal_retile.py \
    -ps "${TILE_SIZE}" "${TILE_SIZE}" \
    -co TILED=YES \
    -co COMPRESS=LZW \
    -targetDir "${TILE_DIR}" \
    warp-60.tif
fi

find "${TILE_DIR}" -name '*.tif' -print | sort | awk '{print NR - 1 "\t" $0}' | while IFS="$(printf '\t')" read -r index tile; do
  base="$(basename "${tile}" .tif)"
  if ! compgen -G "${OUTPUT_DIR}/contour-${base}_*.${OUTPUT_EXTENSION}" >/dev/null; then
    printf '%s\t%s\n' "${index}" "${tile}"
  fi
done | xargs -n 2 -P "${JOBS}" sh -c '
  while [ "$#" -gt 0 ]; do
    index="$1"
    tile="$2"
    shift 2
    base="$(basename "${tile}" .tif)"
    start_id=$((ID_START + index * ID_STRIDE))
    pbf_arg=""
    if [ "${OUTPUT_FORMAT}" = "pbf" ]; then
      pbf_arg="--pbf"
    fi
    "${PHYGHTMAP_BIN}" \
      -o "${OUTPUT_DIR}/contour-${base}" \
      --start-node-id="${start_id}" \
      --start-way-id="${start_id}" \
      --max-nodes-per-tile="${MAX_NODES_PER_TILE}" \
      --max-nodes-per-way="${MAX_NODES_PER_WAY}" \
      -s 10 \
      -0 \
      ${pbf_arg} "${tile}"
  done
' sh
