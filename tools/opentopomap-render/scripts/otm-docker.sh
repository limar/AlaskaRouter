#!/usr/bin/env bash
# Small wrapper around the OpenTopoMap Docker compose file.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="${ROOT}/config/docker-compose.otm.yml"

usage() {
  cat <<EOF
usage: otm-docker.sh <command>

commands:
  up          Start the OpenTopoMap container
  down        Stop the container
  logs        Follow container logs
  shell       Open a shell in the container
  deps        Install/check renderer runtime dependencies
  scripts     Print the first-run import script order
EOF
}

cmd="${1:-}"
case "${cmd}" in
  up)
    docker compose -f "${COMPOSE}" up -d
    ;;
  down)
    docker compose -f "${COMPOSE}" down
    ;;
  logs)
    docker compose -f "${COMPOSE}" logs -f
    ;;
  shell)
    docker compose -f "${COMPOSE}" exec otm-docker bash
    ;;
  deps)
    "${ROOT}/scripts/ensure-otm-deps.sh"
    ;;
  scripts)
    cat <<'EOF'
Before entering the container, run:

  tools/opentopomap-render/scripts/otm-docker.sh deps

Inside the container, run the OpenTopoMap import/preprocess scripts in order.
For SRTM-covered regions, use the upstream DEM script. For Alaska, use the
Copernicus DEM prep script instead of 03_dem_hillshade.sh:

  cd /scripts
  sh 00_setup_database.sh
  sh 01_download_water_polys.sh
  sh 02_import_osm_data.sh
  # Run exactly one DEM prep step:
  sh 03_dem_hillshade.sh                         # SRTM regions
  /alaskarouter-scripts/prepare-copernicus-dem.sh # Alaska/Copernicus regions
  sh 04_preprocess_osm_data.sh
  sh 05_dem_contours1.sh
  CONTOUR_TILE_SIZE=5000 \
    CONTOUR_OUTPUT_FORMAT=xml \
    CONTOUR_OUTPUT_DIR=contours-5000-xml \
    CONTOUR_MAX_NODES_PER_TILE=1000000 \
    CONTOUR_MAX_NODES_PER_WAY=2000 \
    CONTOUR_ID_STRIDE=5000000 \
    /alaskarouter-scripts/prepare-copernicus-contours.sh
  /alaskarouter-scripts/validate-contour-pbf.py \
    --max-way-nodes 5000 \
    --max-id 2000000000 \
    --max-id-span 5000000 \
    /mnt/data/srtm/contours-5000-xml/contour*.osm
  CONTOUR_TILE_SIZE=5000 \
    CONTOUR_OUTPUT_FORMAT=pbf \
    CONTOUR_OUTPUT_DIR=contours-5000 \
    CONTOUR_MAX_NODES_PER_TILE=1000000 \
    CONTOUR_MAX_NODES_PER_WAY=2000 \
    CONTOUR_ID_STRIDE=5000000 \
    /alaskarouter-scripts/prepare-copernicus-contours.sh
  # Run exactly one production contour import step:
  sh 06_dem_contours2.sh                                     # small regions
  /alaskarouter-scripts/import-contours-in-chunks.py \
    --recreate \
    --database contours_probe \
    --pattern 'contour-warp-60_*.osm' \
    --srtm-dir /mnt/data/srtm/contours-5000-xml \
    --cache 32000 \
    --flat-nodes /mnt/db/contours-probe-flat-nodes.bin       # Alaska probe
  /alaskarouter-scripts/import-contours-in-chunks.py \
    --recreate \
    --pattern 'contour-warp-60_*.pbf' \
    --srtm-dir /mnt/data/srtm/contours-5000 \
    --cache 32000 \
    --flat-nodes /mnt/db/contours-flat-nodes.bin              # Alaska

For large regions, run these inside screen/tmux on the server.
EOF
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
