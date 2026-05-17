#!/usr/bin/env bash
# End-to-end FTS5 pipeline: filter OSM, export GeoJSON, build SQLite.
set -euo pipefail
cd "$(dirname "$0")"

./filter_tags.sh
./build_fts5.py
echo
echo "=== Done. DB ready: ../data/pois.sqlite ==="
echo
sqlite3 ../data/pois.sqlite "SELECT category, COUNT(*) FROM place_meta GROUP BY category ORDER BY COUNT(*) DESC LIMIT 40"
