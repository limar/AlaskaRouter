#!/usr/bin/env bash
# Generate contour PBFs from a large Copernicus-derived warp-60.tif in chunks.

set -euo pipefail

SRTM_DIR="${1:-/mnt/data/srtm}"
TILE_SIZE="${CONTOUR_TILE_SIZE:-15000}"
JOBS="${CONTOUR_JOBS:-1}"
ID_START="${CONTOUR_ID_START:-10000000}"
ID_STRIDE="${CONTOUR_ID_STRIDE:-1000000000}"
export ID_START ID_STRIDE

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

find contour-tiles -name '*.tif' -print | sort | awk '{print NR - 1 "\t" $0}' | while IFS="$(printf '\t')" read -r index tile; do
  base="$(basename "${tile}" .tif)"
  if ! compgen -G "contour-${base}_*.pbf" >/dev/null; then
    printf '%s\t%s\n' "${index}" "${tile}"
  fi
done | xargs -n 2 -P "${JOBS}" sh -c '
  while [ "$#" -gt 0 ]; do
    index="$1"
    tile="$2"
    shift 2
    base="$(basename "${tile}" .tif)"
    start_id=$((ID_START + index * ID_STRIDE))
    phyghtmap \
      -o "contour-${base}" \
      --start-node-id="${start_id}" \
      --start-way-id="${start_id}" \
      --max-nodes-per-tile=0 \
      -s 10 \
      -0 \
      --pbf "${tile}"
  done
' sh
