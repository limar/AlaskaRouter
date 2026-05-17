#!/usr/bin/env python3
"""
Build a SQLite FTS5 places DB from a filtered OSM extract.

v2 changes (Spike B.5):
- Glob all `name:*`, `alt_*`, `old_*`, `loc_*`, `official_*`, `short_*`, `nat_*`, `reg_*` tags
  into the `alt_names` column instead of a curated list. Improves recall on indigenous names,
  alt-language spellings, and historical names.
- Dedupe on (lowercased-name, lat-rounded-to-~200m, lon-rounded-to-~200m), keeping the highest
  importance representative. Collapses OSM node/way/relation duplicates of the same logical place.
- Drop the trigram FTS5 table. The spike showed it adds no recall over unicode61+prefix.
- Add a `metadata` table with schema version, build timestamp, and source extract path/mtime
  so anything that consumes the .sqlite knows how to migrate it later.

Input:  data/alaska-filtered.osm.pbf  (produced by filter_tags.sh)
Output: data/pois.sqlite
"""

import hashlib
import json
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
FILTERED_PBF = DATA / "alaska-filtered.osm.pbf"
GEOJSON = DATA / "alaska-filtered.geojson"
DB = DATA / "pois.sqlite"

REGION = "Alaska"
SCHEMA_VERSION = 2

# Round coords for dedupe: 1 decimal degree latitude ≈ 111 km. 4 fractional digits ≈ 11 m,
# 3 ≈ 110 m. We use ROUND_COORD_DIGITS=3 so two POIs within ~150 m collapse.
ROUND_COORD_DIGITS = 3


def categorize(tags: dict) -> str | None:
    if tags.get("amenity") == "fuel": return "fuel"
    if tags.get("amenity") == "drinking_water": return "water"
    if tags.get("amenity") == "ranger_station": return "ranger_station"
    if tags.get("amenity") == "charging_station": return "ev_charging"
    if tags.get("tourism") in {"camp_site", "caravan_site"}: return "camping"
    if tags.get("tourism") in {"alpine_hut", "wilderness_hut"}: return "hut"
    if tags.get("amenity") == "shelter": return "hut"
    if tags.get("tourism") == "information": return "visitor_center"
    if tags.get("tourism") == "viewpoint": return "viewpoint"
    if tags.get("tourism") in {"hotel", "motel", "guest_house", "hostel"}: return "lodging"
    if tags.get("tourism") in {"attraction", "museum"}: return "attraction"
    if tags.get("tourism") == "picnic_site": return "picnic"
    if tags.get("shop") in {"convenience", "supermarket"}: return "store"
    if tags.get("shop") in {"outdoor", "sports", "hunting", "fishing"}: return "outdoor_shop"
    if tags.get("shop") in {"motorcycle", "car_repair", "car_parts"}: return "vehicle_service"
    if tags.get("shop") == "hardware": return "hardware"
    if tags.get("amenity") in {"restaurant", "cafe", "fast_food", "bar", "pub"}: return "food"
    if tags.get("amenity") in {"bank", "atm"}: return "bank"
    if tags.get("amenity") in {"hospital", "clinic"}: return "medical"
    if tags.get("amenity") == "pharmacy": return "pharmacy"
    if tags.get("amenity") == "post_office": return "post"
    if tags.get("amenity") in {"toilets", "shower"}: return "facilities"
    if tags.get("amenity") == "parking": return "parking"
    if tags.get("highway") == "ford": return "river_crossing"
    if tags.get("highway") == "services": return "services"
    if tags.get("natural") == "peak": return "peak"
    if tags.get("natural") == "glacier": return "glacier"
    if tags.get("natural") in {"hot_spring", "spring"}: return "spring"
    if tags.get("natural") == "cave_entrance": return "cave"
    if tags.get("natural") == "volcano": return "volcano"
    if tags.get("waterway") == "waterfall": return "waterfall"
    if tags.get("place") in {"city", "town"}: return "settlement_major"
    if tags.get("place") in {"village", "hamlet", "suburb"}: return "settlement"
    if tags.get("place") in {"locality", "isolated_dwelling"}: return "locality"
    if tags.get("place") == "island": return "island"
    if tags.get("aeroway") == "aerodrome": return "airfield"
    if tags.get("man_made") == "lighthouse": return "lighthouse"
    if tags.get("man_made") == "tower": return "tower"
    if tags.get("historic") in {"monument", "memorial", "castle", "ruins", "wreck"}: return "historic"
    return None


IMPORTANCE = {
    "settlement_major": 1.0,
    "airfield": 0.8,
    "visitor_center": 0.75,
    "peak": 0.7, "glacier": 0.7, "volcano": 0.7,
    "fuel": 0.6,
    "settlement": 0.55,
    "lodging": 0.5, "camping": 0.5, "ranger_station": 0.5, "river_crossing": 0.5,
    "hut": 0.45, "waterfall": 0.45, "hot_spring": 0.45,
    "spring": 0.4, "viewpoint": 0.4, "attraction": 0.4, "lighthouse": 0.4, "island": 0.4,
    "store": 0.35,
    "food": 0.3, "outdoor_shop": 0.3, "vehicle_service": 0.3, "historic": 0.3,
    "ev_charging": 0.3, "medical": 0.3, "services": 0.3, "cave": 0.3,
    "hardware": 0.25, "pharmacy": 0.25,
    "bank": 0.2, "post": 0.2, "water": 0.2, "picnic": 0.2, "tower": 0.2,
    "facilities": 0.15, "locality": 0.15,
    "parking": 0.1,
}


# Heuristic: which OSM keys carry a name-like value worth indexing.
_NAME_KEY_RE = re.compile(
    r"^("
    r"name(:.+)?"        # name, name:en, name:athapaskan, name:ru, …
    r"|alt_name(:.+)?"    # alt_name, alt_name:en, …
    r"|old_name(:.+)?"
    r"|loc_name(:.+)?"
    r"|official_name(:.+)?"
    r"|short_name(:.+)?"
    r"|nat_name(:.+)?"
    r"|reg_name(:.+)?"
    r"|int_name(:.+)?"
    r"|ref"
    r")$"
)


def primary_name(tags: dict) -> str | None:
    """Pick a primary display name. Falls back through a sensible cascade."""
    for k in ("name", "name:en", "official_name", "loc_name", "alt_name", "ref"):
        v = tags.get(k)
        if v:
            return v
    return None


def alt_names(tags: dict, primary: str | None) -> str:
    """Concatenate every name-like OSM tag value except the primary."""
    seen: set[str] = set()
    if primary:
        seen.add(primary.casefold())
    parts: list[str] = []
    for k, v in tags.items():
        if not isinstance(v, str) or not v:
            continue
        if not _NAME_KEY_RE.match(k):
            continue
        if v.casefold() in seen:
            continue
        seen.add(v.casefold())
        parts.append(v)
    return " | ".join(parts)


def export_geojson():
    if GEOJSON.exists() and GEOJSON.stat().st_mtime > FILTERED_PBF.stat().st_mtime:
        print(f"[skip] {GEOJSON} is up-to-date")
        return
    print(f"[osmium] exporting {FILTERED_PBF.name} -> {GEOJSON.name}")
    subprocess.run([
        "osmium", "export",
        "--overwrite",
        "--add-unique-id=type_id",
        "-f", "geojson",
        "-o", str(GEOJSON),
        str(FILTERED_PBF),
    ], check=True)
    print(f"[osmium] done: {GEOJSON.stat().st_size / 1e6:.1f} MB")


def feature_centroid(geom: dict) -> tuple[float, float] | None:
    t = geom["type"]; coords = geom["coordinates"]
    if t == "Point": return (coords[1], coords[0])
    if t in {"LineString", "MultiPoint"} and coords:
        return (sum(c[1] for c in coords)/len(coords), sum(c[0] for c in coords)/len(coords))
    if t == "Polygon" and coords and coords[0]:
        r = coords[0]
        return (sum(c[1] for c in r)/len(r), sum(c[0] for c in r)/len(r))
    if t == "MultiLineString":
        flat = [c for line in coords for c in line]
        if flat:
            return (sum(c[1] for c in flat)/len(flat), sum(c[0] for c in flat)/len(flat))
    if t == "MultiPolygon":
        flat = [c for poly in coords for ring in poly for c in ring]
        if flat:
            return (sum(c[1] for c in flat)/len(flat), sum(c[0] for c in flat)/len(flat))
    return None


def file_md5(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build_db():
    if DB.exists():
        DB.unlink()
    con = sqlite3.connect(DB)
    cur = con.cursor()
    cur.executescript(f"""
    PRAGMA journal_mode=WAL;

    CREATE TABLE metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );

    CREATE TABLE place_meta (
      rowid    INTEGER PRIMARY KEY,
      osm_type TEXT NOT NULL,
      osm_id   INTEGER NOT NULL,
      lat      REAL NOT NULL,
      lon      REAL NOT NULL,
      category TEXT NOT NULL,
      importance REAL NOT NULL,
      name TEXT NOT NULL,
      alt_names TEXT NOT NULL
    );
    CREATE INDEX idx_place_meta_cat ON place_meta(category);

    CREATE VIRTUAL TABLE places_word USING fts5(
      name, alt_names, category, region,
      tokenize = 'unicode61 remove_diacritics 2',
      prefix = '2 3 4 5'
    );
    """)

    print(f"[db] reading {GEOJSON.name}")
    with GEOJSON.open("r", encoding="utf-8") as f:
        data = json.load(f)

    features = data.get("features", [])
    print(f"[db] {len(features):,} raw features")

    # Pass 1: collect candidates.
    candidates: list[tuple[str, int, float, float, str, float, str, str]] = []
    skipped_no_name = 0
    skipped_no_cat = 0
    skipped_no_geom = 0

    for feat in features:
        props = feat.get("properties") or {}
        geom = feat.get("geometry")
        if not geom:
            skipped_no_geom += 1; continue
        category = categorize(props)
        if not category:
            skipped_no_cat += 1; continue
        name = primary_name(props)
        if not name:
            if category == "river_crossing":
                name = "River crossing"
            else:
                skipped_no_name += 1; continue
        centroid = feature_centroid(geom)
        if not centroid:
            skipped_no_geom += 1; continue
        lat, lon = centroid

        oid = props.get("@id") or ""
        if isinstance(oid, str) and oid and oid[0] in "nwr":
            osm_type = {"n": "node", "w": "way", "r": "relation"}[oid[0]]
            try: osm_id = int(oid[1:])
            except ValueError: osm_id = 0
        else:
            osm_type = "unknown"; osm_id = 0

        alts = alt_names(props, name)
        importance = IMPORTANCE.get(category, 0.2)
        candidates.append((osm_type, osm_id, lat, lon, category, importance, name, alts))

    print(f"[db] passed-filter={len(candidates):,} no_name={skipped_no_name:,} no_cat={skipped_no_cat:,} no_geom={skipped_no_geom:,}")

    # Pass 2: dedupe on (name_lower, lat_rounded, lon_rounded). Keep highest importance.
    dedup: dict[tuple[str, float, float], tuple] = {}
    for row in candidates:
        _, _, lat, lon, _, importance, name, _ = row
        key = (name.casefold(), round(lat, ROUND_COORD_DIGITS), round(lon, ROUND_COORD_DIGITS))
        prev = dedup.get(key)
        if prev is None or row[5] > prev[5]:   # row[5] is importance
            dedup[key] = row
    deduped = list(dedup.values())
    collapsed = len(candidates) - len(deduped)
    print(f"[db] deduped: {len(candidates):,} -> {len(deduped):,}  (collapsed {collapsed:,} duplicates)")

    # Pass 3: insert.
    cur.execute("BEGIN")
    for osm_type, osm_id, lat, lon, category, importance, name, alts in deduped:
        cur.execute(
            "INSERT INTO place_meta (osm_type, osm_id, lat, lon, category, importance, name, alt_names) VALUES (?,?,?,?,?,?,?,?)",
            (osm_type, osm_id, lat, lon, category, importance, name, alts),
        )
        rid = cur.lastrowid
        cur.execute(
            "INSERT INTO places_word (rowid, name, alt_names, category, region) VALUES (?,?,?,?,?)",
            (rid, name, alts, category, REGION),
        )

    # Metadata.
    metadata = {
        "schema_version": str(SCHEMA_VERSION),
        "built_at": datetime.now(timezone.utc).isoformat(),
        "region": REGION,
        "source_pbf": FILTERED_PBF.name,
        "source_md5": file_md5(FILTERED_PBF),
        "places_inserted": str(len(deduped)),
        "places_collapsed": str(collapsed),
    }
    for k, v in metadata.items():
        cur.execute("INSERT INTO metadata (key, value) VALUES (?, ?)", (k, v))

    con.commit()
    cur.execute("INSERT INTO places_word(places_word) VALUES('optimize')")
    con.commit()
    cur.execute("VACUUM")
    con.close()

    print(f"[db] inserted={len(deduped):,}")
    print(f"[db] {DB} -> {DB.stat().st_size / 1e6:.1f} MB")
    print(f"[db] metadata: {json.dumps(metadata, indent=2)}")


if __name__ == "__main__":
    if not FILTERED_PBF.exists():
        print(f"missing {FILTERED_PBF}; run filter_tags.sh first", file=sys.stderr)
        sys.exit(1)
    export_geojson()
    build_db()
