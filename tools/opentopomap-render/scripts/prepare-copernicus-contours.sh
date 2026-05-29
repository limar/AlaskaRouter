#!/usr/bin/env bash
# Generate contour PBFs from a large Copernicus-derived warp-60.tif in chunks.

set -euo pipefail

SRTM_DIR="${1:-/mnt/data/srtm}"
TILE_SIZE="${CONTOUR_TILE_SIZE:-15000}"

cd "${SRTM_DIR}"

if [[ ! -f warp-60.tif ]]; then
  echo "Missing ${SRTM_DIR}/warp-60.tif" >&2
  exit 1
fi

rm -rf contour-tiles
rm -f contour*.pbf
mkdir -p contour-tiles

gdal_retile.py \
  -ps "${TILE_SIZE}" "${TILE_SIZE}" \
  -co TILED=YES \
  -co COMPRESS=LZW \
  -targetDir contour-tiles \
  warp-60.tif

find contour-tiles -name '*.tif' -print | sort | while read -r tile; do
  base="$(basename "${tile}" .tif)"
  phyghtmap -o "contour-${base}" --max-nodes-per-tile=0 -s 10 -0 --pbf "${tile}"
done
