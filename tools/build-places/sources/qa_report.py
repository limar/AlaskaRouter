#!/usr/bin/env python3
"""
QA report for the built places DB (AlaskaRouter-lzrh). Run after build_fts5.py
to sanity-check a re-collection: per-source / per-category counts, contact-field
fill rates for overnight categories, and campground/cabin coverage around the
planned Alaska route. Read-only.

Usage:
    sources/qa_report.py                 # report on data/pois.sqlite
    sources/qa_report.py path/to.sqlite
"""

from __future__ import annotations

import sqlite3
import sys
from math import asin, cos, radians, sin, sqrt
from pathlib import Path

from common import DATA_DIR

# A few anchor points along the kind of route this app plans, for a coverage
# spot-check (name, lat, lon).
ROUTE_ANCHORS = [
    ("Anchorage", 61.2181, -149.9003),
    ("Seward", 60.1042, -149.4422),
    ("Soldotna/Kenai", 60.4866, -151.0750),
    ("Denali NP", 63.7283, -148.8867),
    ("Fairbanks", 64.8378, -147.7164),
    ("Tok", 63.3367, -142.9856),
    ("Valdez", 61.1308, -146.3483),
    ("Glennallen", 62.1097, -145.5469),
]
OVERNIGHT = ("camping", "cabin", "hut")


def hav_km(a, b, c, d):
    dlat, dlon = radians(c - a), radians(d - b)
    h = sin(dlat / 2) ** 2 + cos(radians(a)) * cos(radians(c)) * sin(dlon / 2) ** 2
    return 2 * 6371 * asin(sqrt(h))


def main(argv: list[str]) -> int:
    db = Path(argv[1]) if len(argv) > 1 else DATA_DIR / "pois.sqlite"
    if not db.exists():
        raise SystemExit(f"no DB at {db}")
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    cur = con.cursor()
    q = lambda s, *p: cur.execute(s, p).fetchall()

    total = q("SELECT COUNT(*) FROM place_meta")[0][0]
    print(f"\n=== places DB QA — {db}  ({total:,} rows) ===\n")

    print("By source:")
    for src, n in q("SELECT source, COUNT(*) FROM place_meta GROUP BY source ORDER BY 2 DESC"):
        print(f"  {src:14} {n:6,}")

    print("\nOvernight categories (camping/cabin/hut):")
    print(f"  {'category':10} {'rows':>6} {'booking':>8} {'phone':>7} {'website':>8} {'src_url':>8}")
    for cat in OVERNIGHT:
        row = q("""SELECT COUNT(*), SUM(booking_method<>''), SUM(phone<>''),
                          SUM(website<>''), SUM(source_url<>'')
                   FROM place_meta WHERE category=?""", cat)[0]
        n = row[0] or 0
        if not n:
            continue
        pct = lambda x: f"{100*(x or 0)//n:3d}%"
        print(f"  {cat:10} {n:6,} {pct(row[1]):>8} {pct(row[2]):>7} {pct(row[3]):>8} {pct(row[4]):>8}")

    print("\nbooking_method distribution:")
    for bm, n in q("SELECT booking_method, COUNT(*) FROM place_meta WHERE booking_method<>'' GROUP BY 1 ORDER BY 2 DESC"):
        print(f"  {bm:16} {n:5,}")

    print("\nCampground+cabin coverage near route anchors (<= 25 km):")
    rows = q("SELECT lat, lon, category FROM place_meta WHERE category IN ('camping','cabin')")
    for name, lat, lon in ROUTE_ANCHORS:
        near = sum(1 for la, lo, _ in rows if hav_km(lat, lon, la, lo) <= 25)
        print(f"  {name:18} {near:3d}")

    # Metadata provenance
    print("\nProvenance (metadata):")
    for k in ("built_at", "places_collapsed", "external_count", "source_counts"):
        v = q("SELECT value FROM metadata WHERE key=?", k)
        if v:
            print(f"  {k}: {v[0][0]}")
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
