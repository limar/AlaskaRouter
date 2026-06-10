#!/usr/bin/env bash
# Track A (AlaskaRouter-f7tt + xymz): vibrant, contour-free z9-z11.
#
# Two surgical edits to the LIVE style in the container (/home/otm), applied
# at deploy time so the vendored third_party snapshot stays a verbatim
# upstream copy (see third_party/otm-docker/PROVENANCE.md):
#
#  1. basemap-relief.xml: extend the relief-500 color-relief layer from its
#     stock z5-z8 gate up to z11 (&minscale_zoom8; -> &minscale_zoom11;).
#     Above z8 OTM otherwise renders hillshade over WHITE -- that's the whole
#     "washed-out z11" effect. The ramp itself is UNCHANGED (user picked
#     OTM's own ramp, 2026-06-10): z11 simply joins the look of z<=10, and
#     the existing relief-500.tif is reused -- no gdaldem rerun needed.
#
#  2. opentopomap.xml: drop the contours Layer. User decision (xymz): with
#     vibrant relief + hillshade, dense brown contour lines earn nothing for
#     a road-trip planner. Spot heights, not contour webs, if ever needed.
#     (The contour PostGIS db + tooling stay parked; we just stop drawing.)
#
# Idempotent: each edit's pattern no longer matches once applied.
# Run INSIDE the render container:  bash /alaskarouter-scripts/patch-otm-style-vibrant-z11.sh
# Tirex must be restarted afterwards to reload the Mapnik XML (make deps).

set -euo pipefail

OTM_HOME="${OTM_HOME:-/home/otm}"
RELIEF_XML="${OTM_HOME}/styles-otm/basemap-relief.xml"
MAP_XML="${OTM_HOME}/opentopomap.xml"

# --- 1. relief-500: z5-8 -> z5-11 ---------------------------------------
if grep -q '&minscale_zoom8;' "${RELIEF_XML}"; then
  perl -0pi -e 's/&minscale_zoom8;/&minscale_zoom11;/' "${RELIEF_XML}"
  echo "relief-500 gate extended to z11"
else
  grep -q '&minscale_zoom11;' "${RELIEF_XML}" \
    && echo "relief-500 gate already extended (no-op)" \
    || { echo "ERROR: relief-500 gate not found in ${RELIEF_XML}" >&2; exit 1; }
fi

# --- 2. remove the contours Layer ----------------------------------------
if grep -q '<Layer name="contours">' "${MAP_XML}"; then
  perl -0pi -e 's{\s*<Layer name="contours">.*?</Layer>}{}s' "${MAP_XML}"
  echo "contours layer removed"
else
  echo "contours layer already removed (no-op)"
fi

# Sanity: the style must still be loadable XML (entities resolve at parse
# time inside Mapnik; here we just check well-formedness cheaply).
python3 - "$MAP_XML" <<'EOF'
import sys, re
text = open(sys.argv[1]).read()
# strip the DTD entity refs xml.etree can't resolve, then parse
body = re.sub(r'&[a-zA-Z0-9_-]+;', '', text)
import xml.etree.ElementTree as ET
ET.fromstring(body)
print("opentopomap.xml well-formed")
EOF
