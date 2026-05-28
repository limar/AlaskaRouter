#!/usr/bin/env bash
# Fetch a configured Geofabrik PBF into tools/opentopomap-render/data/osm/.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${1:?usage: fetch-osm.sh <region_id>}"
CONFIG="${ROOT}/config/regions.json"
OUTDIR="${ROOT}/data/osm"

mkdir -p "${OUTDIR}"

URL="$(python3 - "${CONFIG}" "${REGION}" <<'PY'
import json, sys
config, region = sys.argv[1], sys.argv[2]
regions = json.load(open(config))["regions"]
if region not in regions:
    raise SystemExit(f"unknown region: {region}")
print(regions[region]["geofabrik_url"])
PY
)"

FILE="${OUTDIR}/${REGION}.osm.pbf"

echo "Fetching ${URL}"
curl -fL --continue-at - --retry 3 --retry-delay 5 \
  --connect-timeout 20 --max-time 1800 \
  --output "${FILE}.tmp" "${URL}"
mv "${FILE}.tmp" "${FILE}"

# Geofabrik publishes sidecar checksums beside extracts. Keep them for manual
# verification and future automation; not every mirror exposes all algorithms.
for suffix in md5 sha256; do
  if curl -fsL --connect-timeout 10 --max-time 30 \
    --output "${FILE}.${suffix}" "${URL}.${suffix}"; then
    echo "Fetched ${FILE}.${suffix}"
  fi
done

echo "Done: ${FILE}"
