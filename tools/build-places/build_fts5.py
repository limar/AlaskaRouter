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

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent      # tools/build-places/
DATA = ROOT / "data"                         # tools/build-places/data/  (gitignored)
FILTERED_PBF = DATA / "alaska-filtered.osm.pbf"
GEOJSON = DATA / "alaska-filtered.geojson"
GNIS_TXT = DATA / "DomesticNames_AK.txt"   # USGS GNIS; fetched by fetch_gnis.sh
WIKIDATA_JSONL = DATA / "wikidata-ak.jsonl"  # Wikidata; fetched by fetch_wikidata.py
DB = DATA / "pois.sqlite"
PLACES_GEOJSON = DATA / "places.geojson"   # AlaskaRouter-vyfe — for map rendering

# Shared source-fetcher contract (sources/common.py). build_fts5 runs as a
# script so ROOT (its own dir) is on sys.path; the `sources` package resolves
# against it. AlaskaRouter-l48r.
sys.path.insert(0, str(ROOT))
from sources.common import (   # noqa: E402  (after sys.path tweak, by design)
    Candidate, read_jsonl, source_of, stable_id,
)

REGION = "Alaska"
# Schema v3 (AlaskaRouter-22h7 milestone 1):
# - Adds `source` column to place_meta ('osm' or 'gnis').
# - Widens categorize() to handle the new OSM tags from the expanded filter
#   (bike/car/boat/motorcycle rentals, ferries, libraries, parks, marinas,
#   coastal features, breweries, guide services, monuments, etc.).
# - Merges USGS GNIS Alaska entries (~30 k natural-feature names). OSM wins
#   on coord-collision dedup; GNIS fills the long tail of named peaks,
#   lakes, capes, bays, glaciers, etc.
SCHEMA_VERSION = 5
# v5 (AlaskaRouter-l48r): add campground/POI enrichment columns to place_meta —
# phone, website, booking_method, open_season, source_url (all TEXT DEFAULT '').
# Populated by the per-source fetchers under sources/ (RIDB, ArcGIS layers,
# scraped directories) and by OSM contact-tag harvesting (Stage 2). The iOS app
# reads place_meta by NAMED columns, so these are backward-compatible: existing
# builds keep working and the columns sit unused until the app surfaces them.
# v4 (AlaskaRouter-b7g0): add `admin_area` column to place_meta. For GNIS
# rows it's the source `county_name` with the borough/census-area suffix
# stripped ("Denali Borough" → "Denali"). For OSM/Wikidata rows it's
# inherited from the nearest GNIS row within ADMIN_INHERIT_KM. Empty when
# no GNIS row is within range. Used by the iOS search-results view in
# place of the lat/lon line: "Denali, AK, USA" / "AK, USA" fallback.

# Radius (km) within which a non-GNIS row inherits the admin_area of the
# nearest GNIS row. 30 km matches Alaska's GNIS density without crossing
# borough boundaries too often. AlaskaRouter-b7g0.
ADMIN_INHERIT_KM = 30.0

# Round coords for the FAST pre-pass dedup: 1 decimal degree latitude ≈ 111 km.
# 4 fractional digits ≈ 11 m, 3 ≈ 110 m. We use ROUND_COORD_DIGITS=3 so two
# POIs within ~150 m collapse via the cheap dict-key path.
ROUND_COORD_DIGITS = 3

# Threshold (km) for the SLOWER second-pass name-based clustering: same name
# within this great-circle distance is treated as one logical feature, even
# when the cheap rounded-coord key didn't catch it (sources disagree by
# 100–500 m on what "centroid" of a feature means; rounded keys then split).
# AlaskaRouter-d1d6. 5 km is generous enough to absorb cross-source centroid
# drift but tight enough that distinct "Smith Creek"-type features in
# different towns stay distinct.
NAME_CLUSTER_KM = 5.0


def categorize(tags: dict) -> str | None:
    # amenity
    if tags.get("amenity") == "fuel": return "fuel"
    if tags.get("amenity") == "drinking_water": return "water"
    if tags.get("amenity") == "ranger_station": return "ranger_station"
    if tags.get("amenity") == "sanitary_dump_station": return "dump_station"  # AlaskaRouter-ix1e
    if tags.get("amenity") == "charging_station": return "ev_charging"
    if tags.get("amenity") in {"bicycle_rental", "motorcycle_rental",
                                "car_rental", "boat_rental"}: return "vehicle_service"
    if tags.get("amenity") == "ferry_terminal": return "marina"
    if tags.get("amenity") in {"community_centre", "library",
                                "toilets", "shower"}: return "facilities"
    if tags.get("amenity") == "shelter": return "hut"
    if tags.get("amenity") in {"restaurant", "cafe", "fast_food", "bar", "pub"}: return "food"
    if tags.get("amenity") in {"bank", "atm"}: return "bank"
    if tags.get("amenity") in {"hospital", "clinic"}: return "medical"
    if tags.get("amenity") == "pharmacy": return "pharmacy"
    if tags.get("amenity") == "post_office": return "post"
    if tags.get("amenity") == "parking": return "parking"
    # tourism
    if tags.get("tourism") in {"camp_site", "caravan_site"}: return "camping"
    if tags.get("tourism") in {"alpine_hut", "wilderness_hut"}: return "hut"
    if tags.get("tourism") == "information": return "visitor_center"
    if tags.get("tourism") == "viewpoint": return "viewpoint"
    if tags.get("tourism") in {"hotel", "motel", "guest_house", "hostel"}: return "lodging"
    if tags.get("tourism") in {"attraction", "museum", "artwork", "gallery"}: return "attraction"
    if tags.get("tourism") == "picnic_site": return "picnic"
    # shop
    if tags.get("shop") in {"convenience", "supermarket"}: return "store"
    if tags.get("shop") in {"outdoor", "sports", "hunting", "fishing"}: return "outdoor_shop"
    if tags.get("shop") in {"motorcycle", "car_repair", "car_parts", "bicycle"}: return "vehicle_service"
    if tags.get("shop") == "hardware": return "hardware"
    # highway
    if tags.get("highway") == "ford": return "river_crossing"
    if tags.get("highway") == "services": return "services"
    # natural
    if tags.get("natural") == "peak": return "peak"
    if tags.get("natural") in {"cliff", "ridge", "saddle"}: return "peak"
    if tags.get("natural") == "glacier": return "glacier"
    if tags.get("natural") in {"hot_spring", "spring"}: return "spring"
    if tags.get("natural") == "cave_entrance": return "cave"
    if tags.get("natural") == "volcano": return "volcano"
    if tags.get("natural") in {"bay", "beach", "reef", "strait",
                                "arch", "fjord"}: return "viewpoint"
    # waterway
    if tags.get("waterway") == "waterfall": return "waterfall"
    # place
    if tags.get("place") in {"city", "town"}: return "settlement_major"
    if tags.get("place") in {"village", "hamlet", "suburb"}: return "settlement"
    if tags.get("place") in {"locality", "isolated_dwelling"}: return "locality"
    if tags.get("place") == "island": return "island"
    # aeroway
    if tags.get("aeroway") in {"aerodrome", "heliport"}: return "airfield"
    # man_made
    if tags.get("man_made") == "lighthouse": return "lighthouse"
    if tags.get("man_made") == "tower": return "tower"
    if tags.get("man_made") in {"monument", "sign", "obelisk",
                                 "memorial", "cairn"}: return "historic"
    if tags.get("man_made") == "pier": return "marina"
    # historic
    if tags.get("historic") in {"monument", "memorial", "castle", "ruins", "wreck"}: return "historic"
    # leisure
    if tags.get("leisure") in {"park", "nature_reserve"}: return "park"
    if tags.get("leisure") in {"marina", "slipway"}: return "marina"
    # boundary (Denali NP, Wrangell-St Elias, etc.)
    if tags.get("boundary") in {"national_park", "protected_area"}: return "park"
    # craft
    if tags.get("craft") in {"brewery", "winery", "distillery", "bakery"}: return "food"
    if tags.get("craft") == "blacksmith": return "historic"
    # office
    if tags.get("office") == "guide": return "outdoor_shop"
    return None


# USGS GNIS feature_class → our category. The classes we deliberately omit are
# either too noisy (`Stream` — 9.3 k Alaska creeks, mostly low-signal individually),
# administrative (`Census`, `Civil`, `Military`, `Area`), or covered by OSM via a
# more specific tag (`Crossing` overlaps `highway=ford`, `Reservoir` shrinks if we
# include all dam-impounded ponds). Revisit `Stream` post-milestone-1 if users
# report missing rivers; the major rivers are also tagged in OSM.
GNIS_CATEGORY: dict[str, str] = {
    # Mountain-family
    "Summit": "peak", "Range": "peak", "Ridge": "peak",
    "Cliff":  "peak", "Gap":   "peak", "Slope": "peak",
    "Bench":  "peak", "Pillar":"peak", "Flat":  "peak",
    "Basin":  "peak", "Valley":"peak",
    # Ice & water
    "Glacier": "glacier", "Crater": "volcano",
    "Lake": "lake", "Reservoir": "lake",
    "Falls": "waterfall", "Rapids": "waterfall",
    "Spring": "spring",
    # Coastal & shore
    "Island": "island",
    "Cape":  "viewpoint", "Bay":     "viewpoint", "Beach":   "viewpoint",
    "Channel":"viewpoint","Gut":     "viewpoint", "Bar":     "viewpoint",
    "Arch":  "viewpoint", "Isthmus": "viewpoint", "Sea":     "viewpoint",
    "Bend":  "viewpoint", "Plain":   "viewpoint", "Canal":   "viewpoint",
    # Settlements (OSM normally wins these via dedup)
    "Populated Place": "settlement",
}


import re as _re

_WORD_RE_CACHE: dict[str, "_re.Pattern[str]"] = {}


def _has(text: str, *keywords: str) -> bool:
    """Return True if any of the keywords appears in `text` as a whole word
    (or word phrase). Single-word matching uses `\\b` regex boundaries so
    'ridge' doesn't false-match 'bridge'; multi-word phrases match the
    whole phrase with boundaries at the edges."""
    for kw in keywords:
        pat = _WORD_RE_CACHE.get(kw)
        if pat is None:
            pat = _re.compile(r"\b" + _re.escape(kw) + r"\b")
            _WORD_RE_CACHE[kw] = pat
        if pat.search(text) is not None:
            return True
    return False


def wikidata_category(types: str) -> str | None:
    """Map a Wikidata item's concatenated type labels (from `wdt:P31`) to
    one of our categories. The labels are human-readable English strings
    like "mountain | extinct volcano | summit", joined by " | ".

    Returns None for items whose type doesn't map cleanly — we'd rather
    drop than mis-categorize. Positive matches come first so terms like
    "borough seat" or "unincorporated community" are recognized as
    settlements before the more aggressive admin-drop pattern below
    would otherwise reject them on "borough" / "unincorporated".

    All matching is word-bounded — 'ridge' will NOT match 'bridge'."""
    t = types.lower()
    if not t:
        return None
    # Settlements — explicit positives first
    if _has(t, "ghost town"): return "historic"      # famous Alaska ones
    if _has(t, "borough seat"): return "settlement_major"
    if _has(t, "capital city", "consolidated city"): return "settlement_major"
    if _has(t, "city", "town"): return "settlement_major"
    if _has(t, "village", "hamlet", "indigenous community",
              "native village", "unincorporated community",
              "human settlement", "populated place"):
        return "settlement"
    # Parks / protected areas (high signal)
    if _has(t, "national park", "national preserve",
              "national monument", "national forest",
              "national wildlife refuge", "wilderness area",
              "state park", "preserve", "wildlife refuge",
              "marine sanctuary"):
        return "park"
    # Natural — mountains & landforms
    if _has(t, "volcano", "crater", "caldera"): return "volcano"
    if _has(t, "mountain", "peak", "summit",
              "ridge", "cliff", "mountain range"): return "peak"
    if _has(t, "glacier"): return "glacier"
    if _has(t, "cave"): return "cave"
    # Water
    if _has(t, "lake"): return "lake"
    if _has(t, "waterfall"): return "waterfall"
    if _has(t, "river", "stream", "creek", "tributary"):
        return "viewpoint"        # named rivers; treat as viewpoint
    if _has(t, "hot spring", "geyser", "spring"): return "spring"
    # Coast & islands
    if _has(t, "island", "archipelago"): return "island"
    if _has(t, "bay", "cove", "harbor", "harbour", "inlet",
              "fjord", "lagoon", "sound", "strait", "channel",
              "passage", "cape", "promontory", "headland",
              "peninsula", "beach", "reef", "isthmus"):
        return "viewpoint"
    # Infrastructure
    if _has(t, "airport", "airfield", "aerodrome",
              "seaplane base", "heliport"):
        return "airfield"
    if _has(t, "lighthouse"): return "lighthouse"
    # Cultural
    if _has(t, "museum", "art gallery"): return "attraction"
    if _has(t, "memorial", "monument", "statue",
              "historic site", "archaeological",
              "national historic landmark", "cultural heritage"):
        return "historic"
    # Final pass: explicit drop list for clearly non-spatial / admin types.
    # Reaches here only if NO positive matcher fired above.
    if _has(t, "neighborhood", "neighbourhood", "borough",
              "census-designated", "subdivision", "election district",
              "school district", "unincorporated area", "geographic region"):
        return None
    # Otherwise drop — too generic / risky to bucket as 'attraction'.
    return None


def wikidata_candidates(path: Path) -> list[tuple]:
    """Read the wikidata-ak.jsonl produced by fetch_wikidata.py and yield
    candidates in the same 8-tuple shape as the OSM / GNIS passes. Each
    line is a single item ({qid, name, lat, lon, types})."""
    if not path.exists():
        print(f"[wikidata] {path.name} not present — skipping "
              f"(run fetch_wikidata.py first)")
        return []
    print(f"[wikidata] reading {path.name}")
    out: list[tuple] = []
    skipped_no_cat = 0
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            category = wikidata_category(row.get("types", ""))
            if category is None:
                skipped_no_cat += 1
                continue
            name = row.get("name", "").strip()
            if not name:
                continue
            try:
                lat = float(row["lat"]); lon = float(row["lon"])
            except (KeyError, ValueError):
                continue
            try:
                qnum = int(str(row.get("qid", "Q0"))[1:])
            except ValueError:
                qnum = 0
            importance = IMPORTANCE.get(category, 0.2)
            # GNIS-style: empty alt_names. Wikidata could supply multilingual
            # names if we extended the SPARQL — out of scope for v1.
            # admin_area starts empty; the inheritance pass after dedup fills
            # it in from the nearest GNIS row within ADMIN_INHERIT_KM (b7g0).
            out.append(Candidate("wikidata", qnum, lat, lon, category, importance, name, "", ""))
    print(f"[wikidata] kept={len(out):,}  unmapped_type={skipped_no_cat:,}")
    return out


def external_candidates(data_dir: Path) -> list[Candidate]:
    """Read every `data/source-*.jsonl` produced by the fetchers under
    sources/ and turn each normalized SourceRecord into a Candidate. Importance
    is assigned here from the shared IMPORTANCE table (keyed on category) so the
    fetchers never need to know our ranking, and the new v5 fields (phone,
    website, booking_method, open_season, source_url) ride straight through.

    Appended to the candidate list AFTER OSM/GNIS/Wikidata for now — external
    rows currently LOSE dedup ties to those three. Stage 6 (AlaskaRouter-lzrh)
    reorders by real source priority (federal > state/local > OSM > GNIS >
    Wikidata > private). AlaskaRouter-l48r."""
    out: list[Candidate] = []
    paths = sorted(data_dir.glob("source-*.jsonl"))
    if not paths:
        print("[source] no data/source-*.jsonl yet — skipping external sources")
        return out
    per_source: dict[str, int] = {}
    for p in paths:
        n = 0
        for rec in read_jsonl(p):
            out.append(Candidate(
                src_type=rec.source,
                src_id=stable_id(rec.source_key),
                lat=float(rec.lat), lon=float(rec.lon),
                category=rec.category,
                importance=IMPORTANCE.get(rec.category, 0.2),
                name=rec.name, alt_names=rec.alt_names, admin_area=rec.admin_area,
                phone=rec.phone, website=rec.website,
                booking_method=rec.booking_method, open_season=rec.open_season,
                source_url=rec.source_url,
            ))
            per_source[rec.source] = per_source.get(rec.source, 0) + 1
            n += 1
        print(f"[source] {p.name}: {n:,} records")
    print(f"[source] external totals: {per_source}")
    return out


def strip_borough_suffix(s: str) -> str:
    """Trim the verbose admin-area suffix GNIS publishes. "Denali Borough" →
    "Denali", "Yukon-Koyukuk Census Area" → "Yukon-Koyukuk", "Juneau, City and
    Borough of" → "Juneau", "Anchorage Municipality" → "Anchorage", "Nome
    (CA)" → "Nome". AlaskaRouter-b7g0.

    Order matters — longest match first. We apply parenthetical suffix
    stripping AFTER the word-suffix pass so "Foo Census Area (CA)" collapses
    correctly to "Foo".
    """
    if not s: return ""
    out = s.strip()
    # Strip trailing parenthetical disambiguators GNIS sometimes uses
    # ("Nome (CA)" — the (CA) marks Census Area).
    paren_tails = [
        " (CA)", "(CA)",
        " (Census Area)", "(Census Area)",
        " (Borough)", "(Borough)",
    ]
    changed = True
    while changed:
        changed = False
        for t in paren_tails:
            if out.endswith(t):
                out = out[: -len(t)].rstrip(", ").strip()
                changed = True
    # Comma forms before non-comma forms so we don't leave a trailing comma.
    suffixes = [
        ", City and Borough of",
        ", Municipality of",
        " City and Borough of",
        " City and Borough",
        " Municipality of",
        " Census Area",
        " Borough",
        " Municipality",
        " County",
        " City",                 # "Sitka City" / "Juneau City" — alt GNIS form
    ]
    for suf in suffixes:
        if out.endswith(suf):
            out = out[: -len(suf)].rstrip(", ").strip()
            break
    # Re-strip parenthetical in case stripping a suffix exposed one.
    changed = True
    while changed:
        changed = False
        for t in paren_tails:
            if out.endswith(t):
                out = out[: -len(t)].rstrip(", ").strip()
                changed = True
    return out


def gnis_candidates(path: Path) -> list[tuple]:
    """Parse a USGS GNIS state .txt (pipe-delimited, header row) and yield
    candidates in the 9-tuple shape (with admin_area). Filters out classes
    not in GNIS_CATEGORY and rows with bad/zero coordinates."""
    if not path.exists():
        print(f"[gnis] {path} not present — skipping (run fetch_gnis.sh first)")
        return []
    print(f"[gnis] reading {path.name}")
    out: list[tuple] = []
    skipped_class: dict[str, int] = {}
    skipped_coord = 0
    with path.open("r", encoding="utf-8-sig") as f:
        header = f.readline().rstrip("\n").split("|")
        # Cache the indexes we care about; tolerate column-order drift between
        # GNIS releases by looking them up by name.
        i_id     = header.index("feature_id")
        i_name   = header.index("feature_name")
        i_class  = header.index("feature_class")
        i_county = header.index("county_name") if "county_name" in header else -1
        i_lat    = header.index("prim_lat_dec")
        # The Alaska file uses 'prim_long_dec' (full word "long"); other vintages
        # have used 'prim_lon_dec'. Accept either.
        i_lon    = header.index("prim_long_dec") if "prim_long_dec" in header \
                   else header.index("prim_lon_dec")
        for line in f:
            row = line.rstrip("\n").split("|")
            if len(row) <= max(i_id, i_name, i_class, i_lat, i_lon):
                continue
            fclass = row[i_class]
            category = GNIS_CATEGORY.get(fclass)
            if category is None:
                skipped_class[fclass] = skipped_class.get(fclass, 0) + 1
                continue
            try:
                lat = float(row[i_lat]); lon = float(row[i_lon])
            except ValueError:
                skipped_coord += 1; continue
            if lat == 0.0 and lon == 0.0:
                skipped_coord += 1; continue
            name = row[i_name].strip()
            if not name:
                continue
            try:
                fid = int(row[i_id])
            except ValueError:
                fid = 0
            admin = ""
            if i_county >= 0 and i_county < len(row):
                admin = strip_borough_suffix(row[i_county])
            importance = IMPORTANCE.get(category, 0.2)
            # GNIS doesn't carry alt names in this file; keep alt_names empty.
            out.append(Candidate("gnis", fid, lat, lon, category, importance, name, "", admin))
    top_skipped = sorted(skipped_class.items(), key=lambda kv: -kv[1])[:6]
    print(f"[gnis] kept={len(out):,}  bad_coords={skipped_coord:,}  "
          f"top_skipped_classes={top_skipped}")
    return out


IMPORTANCE = {
    "settlement_major": 1.0,
    "airfield": 0.8,
    "visitor_center": 0.75,
    "peak": 0.7, "glacier": 0.7, "volcano": 0.7,
    "park": 0.7,                                # Denali, Wrangell-St Elias — high signal
    "fuel": 0.6,
    "settlement": 0.55,
    "lodging": 0.5, "camping": 0.5, "ranger_station": 0.5, "river_crossing": 0.5,
    "cabin": 0.5, "trailhead": 0.45, "boat_launch": 0.4, "dump_station": 0.3,  # AlaskaRouter-l48r

    "hut": 0.45, "waterfall": 0.45, "hot_spring": 0.45,
    "spring": 0.4, "viewpoint": 0.4, "attraction": 0.4, "lighthouse": 0.4, "island": 0.4,
    "lake": 0.4,                                # GNIS named lakes (3k+ in Alaska)
    "marina": 0.4,                              # ferry terminals + slipways + piers
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


# Categories for which OSM contact/booking tags are worth harvesting into the
# v5 columns (Stage 2, AlaskaRouter-ix1e). Scoped to overnight/trip-planning
# POIs — harvesting phone/website for every restaurant/bank would bloat the DB
# for little routing value.
CONTACT_CATEGORIES = {"camping", "lodging", "hut", "picnic",
                      "ranger_station", "visitor_center"}


def extract_contact(tags: dict, osm_type: str, osm_id: int) -> tuple[str, str, str, str, str]:
    """Harvest (phone, website, booking_method, open_season, source_url) from
    an OSM feature's tags. Returns empties when nothing is tagged.

    booking_method is asserted ONLY from explicit booking semantics — we do NOT
    infer `online_portal` from the mere presence of a homepage, because a
    campground website is usually marketing, not a booking portal (house rule:
    don't fabricate data we can't stand behind). Confidence ladder:
      reservation=no                         -> no_reservations
      reservation in {required,yes,...}      -> online_portal (if website) /
                                                phone_email (if phone) / unknown
      fee=no (free site, AK norm: walk-up)   -> walk_in   (best-effort)
      otherwise                              -> "" (unsaid)
    phone/website are still stored regardless, so the app can show "call to
    book" even when booking_method stays "".
    """
    def first(*keys: str) -> str:
        for k in keys:
            v = tags.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()
        return ""

    phone = first("phone", "contact:phone", "contact:mobile")
    website = first("website", "contact:website", "url", "contact:url")
    open_season = first("opening_hours", "opening_hours:camping", "seasonal")

    res = first("reservation").lower()
    fee = first("fee").lower()
    if res == "no":
        booking = "no_reservations"
    elif res in {"required", "yes", "recommended", "members_only", "online"}:
        booking = "online_portal" if website else ("phone_email" if phone else "unknown")
    elif fee == "no":
        booking = "walk_in"
    else:
        booking = ""

    source_url = ""
    if osm_type in {"node", "way", "relation"} and osm_id:
        source_url = f"https://www.openstreetmap.org/{osm_type}/{osm_id}"
    return phone, website, booking, open_season, source_url


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
      alt_names TEXT NOT NULL,
      source   TEXT NOT NULL DEFAULT 'osm',
      admin_area TEXT NOT NULL DEFAULT '',
      -- v5 (AlaskaRouter-l48r) campground/POI enrichment; '' when unknown.
      phone          TEXT NOT NULL DEFAULT '',
      website        TEXT NOT NULL DEFAULT '',
      booking_method TEXT NOT NULL DEFAULT '',
      open_season    TEXT NOT NULL DEFAULT '',
      source_url     TEXT NOT NULL DEFAULT ''
    );
    CREATE INDEX idx_place_meta_cat ON place_meta(category);
    CREATE INDEX idx_place_meta_source ON place_meta(source);

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
    candidates: list[Candidate] = []
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

        # osmium `export --add-unique-id=type_id` writes the id at the Feature
        # top level ("n420361886"), NOT into properties["@id"]. Read it from
        # there; fall back to properties for older exports. (Pre-existing bug:
        # every OSM row was stored osm_type="unknown"/osm_id=0 — fixed here so
        # source_url can be built. AlaskaRouter-ix1e.)
        oid = feat.get("id") or props.get("@id") or ""
        if isinstance(oid, str) and oid and oid[0] in "nwr":
            osm_type = {"n": "node", "w": "way", "r": "relation"}[oid[0]]
            try: osm_id = int(oid[1:])
            except ValueError: osm_id = 0
        else:
            osm_type = "unknown"; osm_id = 0

        alts = alt_names(props, name)
        importance = IMPORTANCE.get(category, 0.2)
        # Harvest contact/booking tags for overnight/trip POIs (Stage 2). Other
        # categories leave the v5 columns empty.
        if category in CONTACT_CATEGORIES:
            phone, website, booking, open_season, source_url = \
                extract_contact(props, osm_type, osm_id)
        else:
            phone = website = booking = open_season = source_url = ""
        # admin_area starts empty; inheritance pass after dedup fills it from
        # the nearest GNIS row within ADMIN_INHERIT_KM (b7g0). OSM features
        # CAN carry admin via the addr:* tags or via admin relations, but we
        # don't extract those today — nearest-GNIS heuristic is enough for v1.
        candidates.append(Candidate(
            osm_type, osm_id, lat, lon, category, importance, name, alts, "",
            phone=phone, website=website, booking_method=booking,
            open_season=open_season, source_url=source_url))

    print(f"[db] osm passed-filter={len(candidates):,} no_name={skipped_no_name:,} no_cat={skipped_no_cat:,} no_geom={skipped_no_geom:,}")
    osm_count = len(candidates)

    # GNIS pass — fills in named natural features (peaks, lakes, glaciers,
    # capes, bays, ridges). Appended AFTER OSM so that when an OSM row and
    # a GNIS row tie on dedup key + importance, OSM's already-installed row
    # wins. (Better tagged, has alt_names, etc.)
    gnis_rows = gnis_candidates(GNIS_TXT)
    candidates.extend(gnis_rows)

    # Wikidata pass — culturally / historically named places that aren't in
    # either OSM (businesses-and-landmarks) or GNIS (US natural-feature names):
    # ghost towns, indigenous communities, museums, national-park boundaries,
    # named historic sites. Appended LAST so OSM and GNIS both win dedup ties.
    wikidata_rows = wikidata_candidates(WIKIDATA_JSONL)
    candidates.extend(wikidata_rows)

    # External sources — every data/source-*.jsonl emitted by the fetchers under
    # sources/ (RIDB, ArcGIS layers, scraped directories). Empty until those
    # stages land, so this is a no-op for the current OSM+GNIS+Wikidata build.
    external_rows = external_candidates(DATA)
    candidates.extend(external_rows)

    # Pass 2a: cheap dict-key dedupe on (name_lower, lat_rounded, lon_rounded).
    # Catches the easy case — same name at the same ~150 m rounded coord.
    # Keep highest importance; on ties, the first-inserted survives (Python
    # dict semantics), which means OSM wins over GNIS over Wikidata.
    dedup: dict[tuple[str, float, float], Candidate] = {}
    for row in candidates:
        key = (row.name.casefold(),
               round(row.lat, ROUND_COORD_DIGITS),
               round(row.lon, ROUND_COORD_DIGITS))
        prev = dedup.get(key)
        if prev is None or row.importance > prev.importance:   # strictly greater
            dedup[key] = row
    stage_a = list(dedup.values())
    after_a = len(stage_a)

    # Pass 2b: name-cluster dedupe (AlaskaRouter-d1d6). Group survivors by
    # casefold name; within each group, run greedy spatial clustering with a
    # 5 km haversine threshold. Same name within 5 km = same logical feature
    # even if the cheap rounded-coord key missed it (cross-source centroid
    # drift, unlucky rounding boundaries, etc).
    #
    # Per-cluster winner: max(importance). On ties, Python's max returns the
    # FIRST occurrence — and we walk stage_a in its original order (OSM
    # first, then GNIS, then Wikidata), so the source-priority tiebreak from
    # 2a is preserved.
    from math import radians, sin, cos, asin, sqrt
    def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        dlat = radians(lat2 - lat1)
        dlon = radians(lon2 - lon1)
        a = sin(dlat/2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon/2)**2
        return 2.0 * 6371.0 * asin(sqrt(a))

    by_name: dict[str, list[tuple]] = {}
    for row in stage_a:
        by_name.setdefault(row[6].casefold(), []).append(row)

    final: list[tuple] = []
    for _, rows in by_name.items():
        if len(rows) == 1:
            final.append(rows[0])
            continue
        # Greedy clustering: each row joins the first existing cluster whose
        # representative (the first row added to it) is within NAME_CLUSTER_KM.
        clusters: list[list[tuple]] = []
        for row in rows:
            lat, lon = row[2], row[3]
            placed = False
            for cluster in clusters:
                rep = cluster[0]
                if haversine_km(lat, lon, rep[2], rep[3]) <= NAME_CLUSTER_KM:
                    cluster.append(row)
                    placed = True
                    break
            if not placed:
                clusters.append([row])
        # Winner per cluster: highest importance; ties → first encountered
        # (OSM-first preference preserved by stage_a ordering).
        for cluster in clusters:
            final.append(max(cluster, key=lambda r: r[5]))

    deduped = final
    collapsed = len(candidates) - len(deduped)
    print(f"[db] deduped: {len(candidates):,} -> after-2a {after_a:,} -> after-2b {len(deduped):,}  (collapsed {collapsed:,} total)")

    # Pass 2c: admin_area inheritance (AlaskaRouter-b7g0).
    # GNIS rows already carry a stripped county/borough name. Non-GNIS rows
    # (OSM, Wikidata) have admin_area="". For each, find the nearest GNIS
    # row with non-empty admin_area within ADMIN_INHERIT_KM and adopt its
    # admin_area. Bbox-prefilter via an integer-degree-lat hash so we don't
    # haversine every donor.
    donors = [(r.lat, r.lon, r.admin_area)
              for r in deduped if r.src_type == "gnis" and r.admin_area]
    donor_by_band: dict[int, list[tuple[float, float, str]]] = {}
    for lat, lon, admin in donors:
        donor_by_band.setdefault(int(lat // 1), []).append((lat, lon, admin))
    # 30 km ≈ 0.27° lat — search ±1 integer band to be safe.
    from math import radians, sin, cos, asin, sqrt
    def hav_km(a_lat, a_lon, b_lat, b_lon):
        dlat = radians(b_lat - a_lat); dlon = radians(b_lon - a_lon)
        h = sin(dlat/2)**2 + cos(radians(a_lat)) * cos(radians(b_lat)) * sin(dlon/2)**2
        return 2.0 * 6371.0 * asin(sqrt(h))

    inherited = 0
    enriched: list[tuple] = []
    for row in deduped:
        if row.admin_area:
            enriched.append(row); continue
        lat, lon = row.lat, row.lon
        band = int(lat // 1)
        best_d = ADMIN_INHERIT_KM + 1.0
        best_admin = ""
        for b in (band - 1, band, band + 1):
            for d_lat, d_lon, d_admin in donor_by_band.get(b, []):
                # Cheap latitude prefilter — same threshold in degrees.
                if abs(d_lat - lat) > 0.30: continue
                dist = hav_km(lat, lon, d_lat, d_lon)
                if dist < best_d:
                    best_d = dist; best_admin = d_admin
        if best_admin and best_d <= ADMIN_INHERIT_KM:
            enriched.append(row._replace(admin_area=best_admin))
            inherited += 1
        else:
            enriched.append(row)
    deduped = enriched
    n_with_admin = sum(1 for r in deduped if r.admin_area)
    print(f"[db] admin_area: {n_with_admin:,}/{len(deduped):,} rows have admin "
          f"({inherited:,} inherited from nearest GNIS within {ADMIN_INHERIT_KM:.0f} km)")

    # Pass 3: insert.
    cur.execute("BEGIN")
    for c in deduped:
        # source is derived from src_type via source_of(): OSM geometry types
        # collapse to "osm"; gnis/wikidata/<external source> pass through.
        source = source_of(c.src_type)
        cur.execute(
            "INSERT INTO place_meta (osm_type, osm_id, lat, lon, category, importance, name, alt_names, source, admin_area, phone, website, booking_method, open_season, source_url) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (c.src_type, c.src_id, c.lat, c.lon, c.category, c.importance, c.name,
             c.alt_names, source, c.admin_area, c.phone, c.website,
             c.booking_method, c.open_season, c.source_url),
        )
        rid = cur.lastrowid
        cur.execute(
            "INSERT INTO places_word (rowid, name, alt_names, category, region) VALUES (?,?,?,?,?)",
            (rid, c.name, c.alt_names, c.category, REGION),
        )

    # Per-source row counts (after dedup) for diagnostics. source_of() folds
    # OSM geometry types into "osm"; everything else is its own source label.
    from collections import Counter
    src_counts = Counter(source_of(r.src_type) for r in deduped)
    n_osm      = src_counts.get("osm", 0)
    n_gnis     = src_counts.get("gnis", 0)
    n_wikidata = src_counts.get("wikidata", 0)
    n_external = sum(v for k, v in src_counts.items()
                     if k not in ("osm", "gnis", "wikidata"))

    # Metadata.
    metadata = {
        "schema_version": str(SCHEMA_VERSION),
        "built_at": datetime.now(timezone.utc).isoformat(),
        "region": REGION,
        "source_pbf": FILTERED_PBF.name,
        "source_md5": file_md5(FILTERED_PBF),
        "source_gnis": GNIS_TXT.name if GNIS_TXT.exists() else "",
        "source_gnis_md5": file_md5(GNIS_TXT) if GNIS_TXT.exists() else "",
        "source_wikidata": WIKIDATA_JSONL.name if WIKIDATA_JSONL.exists() else "",
        "source_wikidata_md5": file_md5(WIKIDATA_JSONL) if WIKIDATA_JSONL.exists() else "",
        "places_inserted": str(len(deduped)),
        "places_collapsed": str(collapsed),
        "osm_count": str(n_osm),
        "gnis_count": str(n_gnis),
        "wikidata_count": str(n_wikidata),
        "external_count": str(n_external),
        "source_counts": json.dumps(dict(src_counts)),
        "osm_pre_dedup": str(osm_count),
        "gnis_pre_dedup": str(len(gnis_rows)),
        "wikidata_pre_dedup": str(len(wikidata_rows)),
        "external_pre_dedup": str(len(external_rows)),
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

    # Companion GeoJSON for map rendering (AlaskaRouter-vyfe).
    # Same rows as place_meta; properties carry the minimum the MapLibre
    # style layers + tap handler need (name, category, importance, source,
    # admin_area). Lat/lon become the GeoJSON Point geometry. Written
    # COMPACT (no indent) — the bundled file is the hot path for app
    # launch + map render, ~5 MB compact vs ~8 MB pretty.
    print(f"[places-geojson] writing {PLACES_GEOJSON.name}")
    features = []
    for c in deduped:
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [c.lon, c.lat]},
            "properties": {
                "name": c.name,
                "category": c.category,
                "importance": c.importance,
                "source": source_of(c.src_type),
                "admin_area": c.admin_area,
            },
        })
    fc = {"type": "FeatureCollection", "features": features}
    with PLACES_GEOJSON.open("w", encoding="utf-8") as f:
        json.dump(fc, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[places-geojson] {PLACES_GEOJSON} -> {PLACES_GEOJSON.stat().st_size / 1e6:.1f} MB "
          f"({len(features):,} features)")


if __name__ == "__main__":
    if not FILTERED_PBF.exists():
        print(f"missing {FILTERED_PBF}; run filter_tags.sh first", file=sys.stderr)
        sys.exit(1)
    export_geojson()
    build_db()
