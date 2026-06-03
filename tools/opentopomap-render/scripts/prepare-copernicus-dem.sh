#!/usr/bin/env bash
# Build OpenTopoMap DEM scratch files from Copernicus GLO-30 COG tiles.

set -euo pipefail

DEM_DIR="${1:-/mnt/data/copernicus-dem}"
SRTM_DIR="${2:-/mnt/data/srtm}"
TARGET_EXTENT="${DEM_TARGET_EXTENT:-}"
DERIVATIVES_ONLY="${DEM_DERIVATIVES_ONLY:-0}"

if [[ "${DERIVATIVES_ONLY}" != "1" ]] && ! compgen -G "${DEM_DIR}/*.tif" >/dev/null; then
  echo "No Copernicus DEM COG files found in ${DEM_DIR}" >&2
  exit 1
fi

mkdir -p "${SRTM_DIR}"
cd "${SRTM_DIR}"

WARP_EXTENT_ARGS=()
if [[ -n "${TARGET_EXTENT}" ]]; then
  read -r MIN_LON MIN_LAT MAX_LON MAX_LAT <<<"${TARGET_EXTENT}"
  WARP_EXTENT_ARGS=(-te_srs EPSG:4326 -te "${MIN_LON}" "${MIN_LAT}" "${MAX_LON}" "${MAX_LAT}")
fi

if [[ "${DERIVATIVES_ONLY}" != "1" ]]; then
  gdalbuildvrt raw.vrt "${DEM_DIR}"/*.tif
  ln -sf raw.vrt raw.tif

  # GDAL 2.4 in jhassler/otm-docker overflows when a full Alaska 30m mosaic is
  # materialized as one source raster. Feed the source COGs directly to gdalwarp
  # so each input raster stays well below that limit. raw.tif remains a VRT
  # compatibility alias for OTM peak/saddle helpers that open that fixed path.
  gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" "${WARP_EXTENT_ARGS[@]}" -r bilinear -tr 1000 1000 "${DEM_DIR}"/*.tif warp-1000.tif
  gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" "${WARP_EXTENT_ARGS[@]}" -r bilinear -tr 5000 5000 "${DEM_DIR}"/*.tif warp-5000.tif
  gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" "${WARP_EXTENT_ARGS[@]}" -r bilinear -tr 500 500 "${DEM_DIR}"/*.tif warp-500.tif
  gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" "${WARP_EXTENT_ARGS[@]}" -r bilinear -tr 60 60 "${DEM_DIR}"/*.tif warp-60.tif
  gdalwarp -co BIGTIFF=YES -co TILED=YES -co COMPRESS=LZW -co PREDICTOR=2 -t_srs "+proj=merc +ellps=sphere +R=6378137 +a=6378137 +units=m" "${WARP_EXTENT_ARGS[@]}" -r bilinear -tr 30 30 "${DEM_DIR}"/*.tif warp-30.tif
fi

for warp in warp-5000.tif warp-1000.tif warp-500.tif warp-30.tif; do
  if [[ ! -f "${warp}" ]]; then
    echo "Missing ${SRTM_DIR}/${warp}; cannot build DEM derivatives" >&2
    exit 1
  fi
done

publish_tif() {
  local tmp="$1"
  local final="$2"
  mv "${tmp}" "${final}"
}

gdaldem color-relief -co COMPRESS=LZW -co PREDICTOR=2 -alpha warp-5000.tif /home/otm/relief_color_text_file.txt relief-5000.tmp.tif
publish_tif relief-5000.tmp.tif relief-5000.tif
gdaldem color-relief -co COMPRESS=LZW -co PREDICTOR=2 -alpha warp-500.tif /home/otm/relief_color_text_file.txt relief-500.tmp.tif
publish_tif relief-500.tmp.tif relief-500.tif

gdaldem hillshade -z 7 -compute_edges -of GTiff -co COMPRESS=JPEG warp-5000.tif hillshade-5000.tmp.tif
publish_tif hillshade-5000.tmp.tif hillshade-5000.tif
gdaldem hillshade -z 7 -compute_edges -of GTiff -co BIGTIFF=YES -co TILED=YES -co COMPRESS=JPEG warp-1000.tif hillshade-1000.tmp.tif
publish_tif hillshade-1000.tmp.tif hillshade-1000.tif
gdaldem hillshade -z 5 -compute_edges -of GTiff -co BIGTIFF=YES -co TILED=YES -co COMPRESS=JPEG warp-500.tif hillshade-500.tmp.tif
publish_tif hillshade-500.tmp.tif hillshade-500.tif
gdaldem hillshade -z 2 -compute_edges -of GTiff -co BIGTIFF=YES -co TILED=YES -co COMPRESS=JPEG warp-30.tif hillshade-30-jpeg.tmp.tif
publish_tif hillshade-30-jpeg.tmp.tif hillshade-30-jpeg.tif
