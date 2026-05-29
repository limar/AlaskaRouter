#!/usr/bin/env bash
# Patch/check runtime tools that the current otm-docker image does not ship.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="${ROOT}/config/docker-compose.otm.yml"

docker compose -f "${COMPOSE}" exec -T otm-docker bash -lc '
set -euo pipefail

if ! command -v gdal_fillnodata.py >/dev/null || ! command -v gdal_merge.py >/dev/null; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y python-gdal
fi

command -v gdal_fillnodata.py
command -v gdal_merge.py

/alaskarouter-scripts/patch-otm-dem-helpers.sh

mkdir -p /mnt/tiles/opentopomap /mnt/tiles/example /mnt/tiles/test
chown -R tirex:tirex /mnt/tiles

service tirex-backend-manager restart
service tirex-master restart
'
