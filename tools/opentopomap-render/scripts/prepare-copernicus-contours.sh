#!/usr/bin/env bash
# Generate contour PBFs from a large Copernicus-derived warp-60.tif in chunks.

set -euo pipefail

SRTM_DIR="${1:-/mnt/data/srtm}"
TILE_SIZE="${CONTOUR_TILE_SIZE:-15000}"
JOBS="${CONTOUR_JOBS:-1}"

cd "${SRTM_DIR}"

if [[ ! -f warp-60.tif ]]; then
  echo "Missing ${SRTM_DIR}/warp-60.tif" >&2
  exit 1
fi

mkdir -p contour-tiles

if ! find contour-tiles -maxdepth 1 -name '*.tif' -print -quit | grep -q .; then
  gdal_retile.py \
    -ps "${TILE_SIZE}" "${TILE_SIZE}" \
    -co TILED=YES \
    -co COMPRESS=LZW \
    -targetDir contour-tiles \
    warp-60.tif
fi

find contour-tiles -name '*.tif' -print | sort | while read -r tile; do
  base="$(basename "${tile}" .tif)"
  if ! compgen -G "contour-${base}_*.pbf" >/dev/null; then
    printf '%s\n' "${tile}"
  fi
done | xargs -n 1 -P "${JOBS}" sh -c '
  for tile do
    base="$(basename "${tile}" .tif)"
    phyghtmap -o "contour-${base}" --max-nodes-per-tile=0 -s 10 -0 --pbf "${tile}"
  done
' sh
