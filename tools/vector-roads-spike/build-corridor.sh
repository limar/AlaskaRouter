#!/usr/bin/env bash
# AlaskaRouter-levi spike: build a MINOR-roads-only vector PMTiles for the
# Dalton Hwy / Galbraith Lake corridor, to overlay on the raster pack.
#
# THE PARTITION INVARIANT (AlaskaRouter-qp29): exactly one layer owns each
# OSM highway class. Our raster z11 draws ONLY the major set (motorway, trunk,
# primary, secondary, tertiary + their _links). This tileset must therefore
# contain ONLY the minor set below -- never add a major class here, or roads
# double-draw.
#
# Laptop-side: needs osmium + tippecanoe (brew). Input is the Geofabrik Alaska
# PBF already fetched by tools/build-places.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PBF="${PBF:-$HERE/../build-places/data/alaska-latest.osm.pbf}"
OUT="${OUT:-$HERE/data}"
# Dalton corridor: Coldfoot/Wiseman -> Atigun Pass -> Galbraith Lake -> Slope Mtn.
BBOX="${BBOX:--151.0,67.0,-148.0,69.0}"

# The vector-owned (minor) classes. Disjoint from the raster's major set.
MINOR="unclassified,residential,living_street,pedestrian,road,service,track,path,footway,cycleway,bridleway,steps"

mkdir -p "$OUT"

osmium extract --overwrite -b "$BBOX" "$PBF" -o "$OUT/corridor.osm.pbf"
osmium tags-filter --overwrite "$OUT/corridor.osm.pbf" \
  "w/highway=${MINOR//,/,}" -o "$OUT/corridor-minor.osm.pbf"
osmium export --overwrite --geometry-types=linestring \
  "$OUT/corridor-minor.osm.pbf" -o "$OUT/corridor-minor.geojsonseq"

# minzoom 8 = low-zoom HEADROOM (display threshold is a runtime style knob);
# maxzoom 14 then crisp vector overzoom beyond.
tippecanoe -o "$OUT/minor-roads.pmtiles" --force \
  --layer=minor_roads \
  --minimum-zoom=8 --maximum-zoom=14 \
  --simplification=4 \
  --include=highway --include=name --include=surface --include=tracktype --include=ref \
  "$OUT/corridor-minor.geojsonseq"

echo "---"
ls -lah "$OUT/minor-roads.pmtiles"
pmtiles show "$OUT/minor-roads.pmtiles"

# Install into the app bundle (gitignored like all *.pmtiles; the Xcode
# project references AlaskaRouter/Resources/minor-roads-spike.pmtiles).
cp "$OUT/minor-roads.pmtiles" "$HERE/../../AlaskaRouter/Resources/minor-roads-spike.pmtiles"
echo "installed -> AlaskaRouter/Resources/minor-roads-spike.pmtiles"
