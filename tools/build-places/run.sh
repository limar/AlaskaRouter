#!/usr/bin/env bash
# End-to-end places-DB pipeline: filter OSM, fetch the long-tail name sources,
# fetch the campground/POI sources, then build the SQLite. Every fetch step is
# idempotent — it skips when its output is already on disk (pass --force to a
# fetcher to refetch). See README.md for sources, keys, and robots posture.
set -euo pipefail
cd "$(dirname "$0")"

# --- Core gazetteer sources (OSM + USGS GNIS + Wikidata) -------------------
./filter_tags.sh
./fetch_gnis.sh
./fetch_wikidata.py

# --- Campground / POI sources (AlaskaRouter-ief3) --------------------------
# RIDB needs RIDB_API_KEY (see .env / .env.example); ArcGIS + ACOA are keyless.
# These fail LOUD if a source is unreachable or the key is missing — by design.
./sources/fetch_ridb.py
./sources/fetch_arcgis.py
./sources/scrape_acoa.py

# --- Merge + build ----------------------------------------------------------
./build_fts5.py
echo
echo "=== Done. DB ready: tools/build-places/data/pois.sqlite ==="
echo "    (cp it to AlaskaRouter/Resources/alaska-places.sqlite to ship.)"
echo
./sources/qa_report.py
