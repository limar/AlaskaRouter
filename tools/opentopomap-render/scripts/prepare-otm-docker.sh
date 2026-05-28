#!/usr/bin/env bash
# Prepare the otm-docker data layout for a configured render region.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${1:?usage: prepare-otm-docker.sh <region_id>}"
CONFIG="${ROOT}/config/regions.json"
DATA_ROOT="${ROOT}/data"
OSM_DIR="${DATA_ROOT}/osm"
DOCKER_DATA="${DATA_ROOT}/docker/data"

PBF="${OSM_DIR}/${REGION}.osm.pbf"
if [[ ! -f "${PBF}" ]]; then
  echo "Missing ${PBF}" >&2
  echo "Run: ${ROOT}/scripts/fetch-osm.sh ${REGION}" >&2
  exit 1
fi

mkdir -p \
  "${DOCKER_DATA}/srtm" \
  "${DATA_ROOT}/docker/db" \
  "${DATA_ROOT}/docker/tablespace" \
  "${DATA_ROOT}/docker/letsencrypt"
ln -sf "/osm/${REGION}.osm.pbf" "${DOCKER_DATA}/osmdata.pbf"

python3 - "${CONFIG}" "${REGION}" "${DATA_ROOT}/docker/REGION.txt" <<'PY'
import json, pathlib, sys
config, region_id, out = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
region = json.load(open(config))["regions"][region_id]
out.write_text(
    "\n".join([
        f"region={region_id}",
        f"title={region['title']}",
        f"bbox={','.join(str(v) for v in region['bbox'])}",
        f"zooms={','.join(str(v) for v in region['zooms'])}",
        "",
    ])
)
PY

echo "Prepared otm-docker data layout for ${REGION}"
echo "PBF: ${DOCKER_DATA}/osmdata.pbf -> /osm/${REGION}.osm.pbf"
echo "Host PBF source: ${PBF}"
echo "SRTM directory: ${DOCKER_DATA}/srtm"
echo "Tablespace directory: ${DATA_ROOT}/docker/tablespace"
echo "Next: add SRTM ZIP/HGT files covering the region, then run scripts/otm-docker.sh up"
