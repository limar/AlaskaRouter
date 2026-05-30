#!/usr/bin/env bash
# Generate contour files from a large Copernicus-derived warp-60.tif in chunks.

set -euo pipefail

SRTM_DIR="${1:-/mnt/data/srtm}"
TILE_SIZE="${CONTOUR_TILE_SIZE:-5000}"
JOBS="${CONTOUR_JOBS:-1}"
ID_START="${CONTOUR_ID_START:-10000000}"
ID_STRIDE="${CONTOUR_ID_STRIDE:-5000000}"
MAX_NODES_PER_TILE="${CONTOUR_MAX_NODES_PER_TILE:-1000000}"
MAX_NODES_PER_WAY="${CONTOUR_MAX_NODES_PER_WAY:-2000}"
TILE_DIR="${CONTOUR_TILE_DIR:-contour-tiles-${TILE_SIZE}}"
OUTPUT_DIR="${CONTOUR_OUTPUT_DIR:-contours-${TILE_SIZE}}"
OUTPUT_FORMAT="${CONTOUR_OUTPUT_FORMAT:-pbf}"

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

export ID_START ID_STRIDE MAX_NODES_PER_TILE MAX_NODES_PER_WAY OUTPUT_DIR OUTPUT_FORMAT

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
    phyghtmap \
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
