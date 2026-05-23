#!/usr/bin/env bash
# Fetch USGS GNIS Domestic Names — Alaska state file.
#
# USGS GNIS (Geographic Names Information System) is the US government's
# authoritative database of geographic feature names. Public domain. Refreshed
# periodically by the U.S. Board on Geographic Names. The Alaska state file has
# ~30 k entries covering peaks, glaciers, lakes, capes, bays, islands, falls,
# springs, etc. — coverage that's far stronger than OSM for natural features.
#
# Output: data/DomesticNames_AK.txt (pipe-delimited, 21 columns; see header row).
# Idempotent: skips download when the .txt already exists.
set -euo pipefail
cd "$(dirname "$0")/../data"

URL="https://prd-tnm.s3.amazonaws.com/StagedProducts/GeographicNames/DomesticNames/DomesticNames_AK_Text.zip"
ZIP="DomesticNames_AK_Text.zip"
TXT="DomesticNames_AK.txt"

if [[ -f "$TXT" ]]; then
  echo "[skip] $TXT already present ($(wc -l < "$TXT" | tr -d ' ') lines)"
  exit 0
fi

echo "[fetch] $URL"
curl -fsSL --progress-bar -o "$ZIP" "$URL"

echo "[unzip] $ZIP -> $TXT"
# -j junks paths so the .txt drops directly into data/ (skipping the inner Text/ dir).
unzip -j -o "$ZIP" 'Text/DomesticNames_AK.txt' -d .
rm -f "$ZIP"
ls -lh "$TXT"
