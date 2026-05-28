#!/usr/bin/env bash
# Build OpenTopoMap DEM scratch files from Copernicus GLO-30 COG tiles.

set -euo pipefail

DEM_DIR="${1:-/mnt/data/copernicus-dem}"
SRTM_DIR="${2:-/mnt/data/srtm}"

if ! compgen -G "${DEM_DIR}/*.tif" >/dev/null; then
  echo "No Copernicus DEM COG files found in ${DEM_DIR}" >&2
  exit 1
fi

mkdir -p "${SRTM_DIR}"
cd "${SRTM_DIR}"

gdalbuildvrt raw.vrt "${DEM_DIR}"/*.tif

# GDAL 2.4 in jhassler/otm-docker overflows when a full Alaska 30m mosaic is
# materialized as one source raster. Feed the source COGs directly to gdalwarp
# so each input raster stays well below that limit.
gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" -r bilinear -tr 1000 1000 "${DEM_DIR}"/*.tif warp-1000.tif
gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" -r bilinear -tr 5000 5000 "${DEM_DIR}"/*.tif warp-5000.tif
gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" -r bilinear -tr 500 500 "${DEM_DIR}"/*.tif warp-500.tif
gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" -r bilinear -tr 60 60 "${DEM_DIR}"/*.tif warp-60.tif
gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" -r bilinear -tr 30 30 "${DEM_DIR}"/*.tif warp-30.tif

gdaldem color-relief -co COMPRESS=LZW -co PREDICTOR=2 -alpha warp-5000.tif /home/otm/relief_color_text_file.txt relief-5000.tif
gdaldem color-relief -co COMPRESS=LZW -co PREDICTOR=2 -alpha warp-500.tif /home/otm/relief_color_text_file.txt relief-500.tif

gdaldem hillshade -z 7 -compute_edges -co COMPRESS=JPEG warp-5000.tif hillshade-5000.tif
gdaldem hillshade -z 7 -compute_edges -co BIGTIFF=YES -co TILED=YES -co COMPRESS=JPEG warp-1000.tif hillshade-1000.tif
gdaldem hillshade -z 5 -compute_edges -co BIGTIFF=YES -co TILED=YES -co COMPRESS=JPEG warp-500.tif hillshade-500.tif
gdaldem hillshade -z 2 -co compress=lzw -co predictor=2 -co bigtiff=yes -compute_edges warp-30.tif hillshade-30.tif
gdal_translate -co compress=JPEG -co bigtiff=yes -co tiled=yes hillshade-30.tif hillshade-30-jpeg.tif
