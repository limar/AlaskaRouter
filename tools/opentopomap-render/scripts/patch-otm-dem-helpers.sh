#!/usr/bin/env bash
# Patch OpenTopoMap DEM helper tools for regional Copernicus/VRT inputs.

set -euo pipefail

TOOLS_DIR="${1:-/scripts/tools}"

perl -0pi -e 's/GDALRegister_GTiff\(\);/GDALAllRegister();/g' \
  "${TOOLS_DIR}/isolation.c" \
  "${TOOLS_DIR}/saddledirection.c"

perl -0pi -e 's/ area2x2=malloc\(4\*sizeof\(int16_t\)\);/ if((xpx<0)||(xpx>=xsize-1)||(ypx<0)||(ypx>=ysize-1)){return 0.0;}\n\n area2x2=malloc(4*sizeof(int16_t));/' \
  "${TOOLS_DIR}/isolation.c"

perl -0pi -e 's/  w=ri-le;h=dw-up;\n  \n\/\* get all DEM values/  w=ri-le;h=dw-up;\n  if(w <= 0 || h <= 0){continue;}\n\n\/\* get all DEM values/' \
  "${TOOLS_DIR}/isolation.c"
