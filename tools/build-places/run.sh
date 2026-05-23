#!/usr/bin/env bash
# End-to-end FTS5 pipeline: filter OSM, fetch GNIS, export GeoJSON,
# build SQLite. fetch_gnis.sh is idempotent — it skips when the
# file is already on disk.
set -euo pipefail
cd "$(dirname "$0")"

./filter_tags.sh
./fetch_gnis.sh
./build_fts5.py
echo
echo "=== Done. DB ready: tools/build-places/data/pois.sqlite ==="
echo "    (cp it to AlaskaRouter/Resources/alaska-places.sqlite to ship.)"
echo
sqlite3 data/pois.sqlite "SELECT category, COUNT(*) FROM place_meta GROUP BY category ORDER BY COUNT(*) DESC LIMIT 40"
