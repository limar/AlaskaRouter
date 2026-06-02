#!/usr/bin/env python3
"""
Common contract for AlaskaRouter places-DB source fetchers (AlaskaRouter-l48r).

Every data source under tools/build-places/sources/ (RIDB, ArcGIS layers,
scraped directories, …) normalizes its records into `SourceRecord` and writes
them as `data/source-<name>.jsonl` (one JSON object per line) via `write_jsonl`.
`build_fts5.py` then globs `data/source-*.jsonl`, turns each record into the
internal `Candidate`, assigns importance, and feeds them through the SAME
coord+name dedup that OSM / GNIS / Wikidata already use.

Keeping this contract tiny and explicit is what makes the collection effort
repeatable: adding a source is "write a fetcher that emits SourceRecords",
nothing more. No fetcher needs to know anything about SQLite, FTS5, dedup, or
the app. This module has NO third-party dependencies on purpose.
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Iterator, NamedTuple

# tools/build-places/ (parent of this sources/ package) and its conventional
# locations. Fetchers import these so every source writes to the same data dir
# and reads keys from the same gitignored .env.
BUILD_PLACES_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BUILD_PLACES_DIR / "data"
ENV_FILE = BUILD_PLACES_DIR / ".env"


def load_env() -> None:
    """Load tools/build-places/.env into os.environ (without overriding values
    already exported). Tiny KEY=VALUE parser — no python-dotenv dependency.
    `.env` is gitignored; see .env.example."""
    if not ENV_FILE.exists():
        return
    for raw in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


def require_env(name: str, hint: str) -> str:
    """Fetch a required secret from the environment (or .env). Fail LOUD with
    an actionable hint when missing — house rule: no silent fallbacks."""
    load_env()
    v = os.environ.get(name, "").strip()
    if not v:
        raise SystemExit(f"[fatal] env var {name} is not set.\n  {hint}")
    return v


# --------------------------------------------------------------------------- #
# Internal pipeline row — what build_fts5's dedup engine consumes.
# --------------------------------------------------------------------------- #
# A NamedTuple, NOT a plain tuple, so the dedup engine's legacy positional
# access (row[5] == importance, row[:8], max(key=lambda r: r[5]), …) keeps
# working unchanged, while new code can read row.phone / row.booking_method by
# name. Fields 0-8 match the historical 9-tuple exactly; 9-13 are the schema-v5
# campground columns, all defaulting to "" so existing 9-arg construction sites
# (OSM / GNIS / Wikidata) compile untouched.
class Candidate(NamedTuple):
    src_type: str             # 0  node|way|relation|unknown|gnis|wikidata|<source>
    src_id: int               # 1  osm id | gnis feature_id | wikidata qnum | hash
    lat: float                # 2
    lon: float                # 3
    category: str             # 4
    importance: float         # 5
    name: str                 # 6
    alt_names: str = ""       # 7
    admin_area: str = ""      # 8
    phone: str = ""           # 9   v5
    website: str = ""         # 10  v5
    booking_method: str = ""  # 11  v5  see BOOKING_METHODS
    open_season: str = ""     # 12  v5  free text, e.g. "May–Sep"
    source_url: str = ""      # 13  v5  original record URL, for traceability


# OSM features encode their source via the geometry type in src_type; every
# other src_type value already IS the canonical source label.
OSM_SRC_TYPES = {"node", "way", "relation", "unknown"}

# Allowed booking_method values (matches the investigation's enum). "" = the
# source didn't say anything; "unknown" = the source said something we couldn't
# classify. Keep them distinct.
BOOKING_METHODS = {
    "online_portal",
    "phone_email",
    "walk_in",
    "no_reservations",
    "unknown",
    "",
}


def source_of(src_type: str) -> str:
    """Canonical `source` label stored in place_meta.source. OSM
    node/way/relation/unknown collapse to 'osm'; every other src_type
    (gnis, wikidata, ridb, ak_dnr_parks, …) is already the source label."""
    return "osm" if src_type in OSM_SRC_TYPES else src_type


def stable_id(source_key: str) -> int:
    """Deterministic positive 56-bit int from an arbitrary source key (URL,
    GUID, facility id). Lets external sources populate the INTEGER osm_id slot
    with something stable and roughly-unique for debugging / future shared-id
    dedup, without colliding with real OSM ids (which are << 2^56 today but
    we don't mix the two in dedup anyway — src_type disambiguates)."""
    return int.from_bytes(hashlib.sha1(source_key.encode("utf-8")).digest()[:7], "big")


# --------------------------------------------------------------------------- #
# Fetcher-facing normalized record.
# --------------------------------------------------------------------------- #
@dataclass
class SourceRecord:
    source: str               # canonical source label, e.g. "ridb"
    source_key: str           # stable per-source id or URL (dedup + traceability)
    name: str
    lat: float
    lon: float
    category: str             # one of build_fts5's category keys
    alt_names: str = ""
    admin_area: str = ""
    phone: str = ""
    website: str = ""
    booking_method: str = ""  # see BOOKING_METHODS
    open_season: str = ""
    source_url: str = ""

    def validate(self) -> None:
        if not self.source or not self.name:
            raise ValueError(f"SourceRecord missing source/name: {self!r}")
        try:
            lat = float(self.lat)
            lon = float(self.lon)
        except (TypeError, ValueError) as e:
            raise ValueError(f"SourceRecord non-numeric coords: {self!r}") from e
        if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lon <= 180.0):
            raise ValueError(f"SourceRecord out-of-range coords: {self!r}")
        if lat == 0.0 and lon == 0.0:
            raise ValueError(f"SourceRecord null-island coords: {self!r}")
        if not self.category:
            raise ValueError(f"SourceRecord missing category: {self!r}")
        if self.booking_method not in BOOKING_METHODS:
            raise ValueError(
                f"SourceRecord bad booking_method {self.booking_method!r}: {self!r}"
            )


def write_jsonl(records: Iterable[SourceRecord], path: Path) -> int:
    """Write records to `path` as JSONL. Validates each (fail loud — house
    rule: no silent dropping of malformed rows). Returns the count written."""
    path.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with path.open("w", encoding="utf-8") as f:
        for r in records:
            r.validate()
            f.write(json.dumps(asdict(r), ensure_ascii=False) + "\n")
            n += 1
    return n


def read_jsonl(path: Path) -> Iterator[SourceRecord]:
    """Read a `data/source-*.jsonl` file back into SourceRecords."""
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            yield SourceRecord(**json.loads(line))


# --------------------------------------------------------------------------- #
# Shared helpers for fetchers.
# --------------------------------------------------------------------------- #
# Acronyms / connectives for title-casing ALL-CAPS source names (RIDB, KPB).
_KEEP_UPPER = {"RV", "NF", "NM", "NP", "BLM", "USFS", "USFWS", "ATV", "OHV",
               "US", "USA", "II", "III", "IV", "ADA", "CG", "KPB", "ASP"}
_KEEP_LOWER = {"of", "the", "and", "at", "on", "in", "to", "by", "for", "de"}


def smart_title(name: str) -> str:
    """Title-case an ALL-CAPS name ("BERNICE LAKE CAMPGROUND") while preserving
    known acronyms and lowercasing connectives. Mixed-case names (already
    human-formatted) are returned unchanged."""
    name = (name or "").strip()
    if not name or any(c.islower() for c in name):
        return name
    out: list[str] = []
    for i, w in enumerate(name.split()):
        u = w.strip(".,").upper()
        if u in _KEEP_UPPER:
            out.append(u)
        elif i > 0 and w.lower() in _KEEP_LOWER:
            out.append(w.lower())
        else:
            out.append(w[:1].upper() + w[1:].lower())
    return " ".join(out)


def geojson_centroid(geom: dict | None) -> tuple[float, float] | None:
    """(lat, lon) centroid of a GeoJSON geometry. Mean of coords for poly/line,
    direct for points. Returns None for empty/unsupported geometry."""
    if not geom:
        return None
    t = geom.get("type")
    c = geom.get("coordinates")
    if not c and t != "GeometryCollection":
        return None
    if t == "Point":
        return (c[1], c[0])
    if t in ("MultiPoint", "LineString"):
        pts = c
    elif t == "MultiLineString" or t == "Polygon":
        pts = [p for part in c for p in part]
    elif t == "MultiPolygon":
        pts = [p for poly in c for ring in poly for p in ring]
    else:
        return None
    if not pts:
        return None
    return (sum(p[1] for p in pts) / len(pts),
            sum(p[0] for p in pts) / len(pts))
