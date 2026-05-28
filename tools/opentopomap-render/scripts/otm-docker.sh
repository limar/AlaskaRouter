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
  scripts)
    cat <<'EOF'
Inside the container, run the OpenTopoMap import/preprocess scripts in order:

  cd /scripts
  sh 00_setup_database.sh
  sh 01_download_water_polys.sh
  sh 02_import_osm_data.sh
  sh 03_dem_hillshade.sh
  sh 04_preprocess_osm_data.sh
  sh 05_dem_contours1.sh
  sh 06_dem_contours2.sh

For large regions, run these inside screen/tmux on the server.
EOF
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
