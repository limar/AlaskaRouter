#!/usr/bin/env python3
"""
Fetch Alaska federal recreation facilities from the Recreation Information
Database (RIDB) — the official API behind Recreation.gov. AlaskaRouter-lyog.

RIDB is the authoritative federal source for campgrounds (Forest Service,
NPS, BLM, Corps of Engineers, F&W) plus adjacent recreation facilities
(cabins, trailheads, day-use sites, visitor centers). ~277 facilities in AK.

Output: data/source-ridb.jsonl (normalized SourceRecords; consumed by
build_fts5.py via the data/source-*.jsonl glob).

Auth: needs a free RIDB API key in env RIDB_API_KEY (or tools/build-places/.env).
Get one at https://ridb.recreation.gov/ -> sign in -> Profile -> "API Key".

Idempotent: skips when data/source-ridb.jsonl already exists; pass --force to
refetch. 429/5xx are retried with exponential backoff (RIDB etiquette).

Usage:
    sources/fetch_ridb.py            # fetch unless the output already exists
    sources/fetch_ridb.py --force    # always refetch
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# Allow running as a plain script (sources/fetch_ridb.py) by putting the
# package parent on the path so `from common import …` resolves.
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from common import (  # noqa: E402
    DATA_DIR, SourceRecord, require_env, write_jsonl,
)

API = "https://ridb.recreation.gov/api/v1/facilities"
STATE = "AK"
# RIDB offset-paging is UNSTABLE without an explicit sort (an unsorted full
# pass over AK returns 277 rows but only ~233 unique — duplicates in, distinct
# facilities missed). sort=Name makes paging deterministic. PAGE is large
# enough that AK fits in one request anyway (belt and suspenders).
PAGE = 1000
SORT = "Name"
OUT = DATA_DIR / "source-ridb.jsonl"
SOURCE = "ridb"
KEY_HINT = ("Get a free key at https://ridb.recreation.gov/ (sign in -> Profile "
            "-> API Key), then put RIDB_API_KEY=<key> in tools/build-places/.env "
            "or export it.")

# Acronyms / small words to preserve when title-casing ALL-CAPS RIDB names.
_KEEP_UPPER = {"RV", "NF", "NM", "NP", "BLM", "USFS", "USFWS", "ATV", "OHV",
               "US", "USA", "II", "III", "IV", "ADA", "CG"}
_KEEP_LOWER = {"of", "the", "and", "at", "on", "in", "to", "by", "for", "de"}


def smart_title(name: str) -> str:
    """RIDB returns many names ALL-CAPS ("SARKAR LAKE CABIN"). Title-case those
    while preserving known acronyms and lowercasing connectives. Mixed-case
    names (already human-formatted) are left untouched."""
    name = name.strip()
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


def classify(name: str, ftype: str) -> str | None:
    """Map an RIDB facility to one of build_fts5's categories. Non-spatial
    booking products (Permit / Ticket Facility — road lotteries, tours, permit
    bundles) return None and are dropped: they're not places. Everything else
    (campgrounds AND adjacent recreation facilities) is kept, classified by
    name keyword first, then FacilityTypeDescription. AlaskaRouter-lyog."""
    if ftype in {"Permit", "Ticket Facility"}:
        return None
    n = name.upper()
    # Keyword ladder — order matters (most specific first).
    if "CABIN" in n or "YURT" in n:                       return "cabin"
    if "TRAILHEAD" in n or "TRAIL HEAD" in n:             return "trailhead"
    if ("BOAT LAUNCH" in n or "BOAT RAMP" in n
            or "LAUNCH" in n or " RAMP" in n or "LANDING" in n): return "boat_launch"
    if "VISITOR CENTER" in n or "VISITORS CENTER" in n:   return "visitor_center"
    if "RANGER STATION" in n:                             return "ranger_station"
    if "PICNIC" in n or "DAY USE" in n:                   return "picnic"
    if ("WAYSIDE" in n or "OVERLOOK" in n or "VIEWPOINT" in n
            or "VIEWING" in n or "SCENIC" in n):          return "viewpoint"
    if ("WILDERNESS" in n or "RECREATION AREA" in n or "STATE PARK" in n
            or "NATIONAL FOREST" in n or "PRESERVE" in n or "REFUGE" in n
            or "NATIONAL PARK" in n or n.endswith(" PARK")): return "park"
    if "CAMPGROUND" in n or "CAMP" in n or "CG" in n:     return "camping"
    # Fallbacks by RIDB type.
    if ftype == "Campground":
        return "camping"
    # Unmatched "Facility" rows are typically recreation/management areas.
    return "park"


def fetch_page(key: str, offset: int, max_attempts: int = 5) -> dict:
    params = urllib.parse.urlencode(
        {"state": STATE, "limit": PAGE, "offset": offset, "sort": SORT})
    url = f"{API}?{params}"
    last = None
    for attempt in range(1, max_attempts + 1):
        req = urllib.request.Request(
            url, headers={"apikey": key, "accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            last = e
            if e.code in (429, 500, 502, 503, 504):
                wait = int(e.headers.get("Retry-After", 0)) or min(60, 5 * 2 ** (attempt - 1))
                print(f"[ridb] HTTP {e.code} — sleeping {wait}s "
                      f"(attempt {attempt}/{max_attempts})")
                time.sleep(wait)
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last = e
            wait = min(60, 5 * 2 ** (attempt - 1))
            print(f"[ridb] {type(e).__name__}: {e} — sleeping {wait}s "
                  f"(attempt {attempt}/{max_attempts})")
            time.sleep(wait)
    raise RuntimeError(f"RIDB failed after {max_attempts} attempts: {last}")


def to_record(f: dict) -> SourceRecord | None:
    fid = str(f.get("FacilityID") or "").strip()
    name = smart_title(f.get("FacilityName") or "")
    ftype = f.get("FacilityTypeDescription") or ""
    if not fid or not name:
        return None
    category = classify(name, ftype)
    if category is None:
        return None
    try:
        lat = float(f.get("FacilityLatitude") or 0.0)
        lon = float(f.get("FacilityLongitude") or 0.0)
    except (TypeError, ValueError):
        return None
    if lat == 0.0 and lon == 0.0:
        return None  # RIDB leaves ~9 AK facilities ungeocoded

    phone = (f.get("FacilityPhone") or "").strip()
    reservable = bool(f.get("Reservable"))
    # Reservations on Recreation.gov are by FacilityID (the per-facility
    # ReservationURL field is empty for AK). Assert online_portal only when the
    # facility is actually reservable; otherwise leave booking_method unknown
    # rather than guessing first-come (house rule: don't fabricate).
    booking = "online_portal" if reservable else ""
    # Reservable facilities (campgrounds AND cabins — both are "campgrounds" in
    # the Recreation.gov taxonomy) deep-link to their booking page. Otherwise
    # fall back to RIDB's map URL when present.
    source_url = (f"https://www.recreation.gov/camping/campgrounds/{fid}"
                  if reservable
                  else (f.get("FacilityMapURL") or "").strip())

    rec = SourceRecord(
        source=SOURCE, source_key=fid, name=name, lat=lat, lon=lon,
        category=category, phone=phone, booking_method=booking,
        source_url=source_url,
    )
    return rec


def main(argv: list[str]) -> int:
    force = "--force" in argv[1:]
    if OUT.exists() and OUT.stat().st_size > 0 and not force:
        n = sum(1 for _ in OUT.open())
        print(f"[skip] {OUT.name} already present ({n:,} records). Use --force to refetch.")
        return 0
    key = require_env("RIDB_API_KEY", KEY_HINT)

    print(f"[ridb] fetching AK facilities (page size {PAGE})...")
    records: list[SourceRecord] = []
    seen: set[str] = set()
    dropped_permit = dropped_nogeo = dropped_dup = 0
    offset = 0
    total = None
    while True:
        d = fetch_page(key, offset)
        if total is None:
            total = d["METADATA"]["RESULTS"]["TOTAL_COUNT"]
            print(f"[ridb] total AK facilities reported: {total}")
        rd = d.get("RECDATA", [])
        if not rd:
            break
        for f in rd:
            ftype = f.get("FacilityTypeDescription") or ""
            rec = to_record(f)
            if rec is None:
                if ftype in {"Permit", "Ticket Facility"}:
                    dropped_permit += 1
                else:
                    dropped_nogeo += 1
                continue
            if rec.source_key in seen:
                dropped_dup += 1
                continue
            seen.add(rec.source_key)
            records.append(rec)
        offset += PAGE
        if offset >= total:
            break
        time.sleep(0.3)  # be polite

    n = write_jsonl(records, OUT)
    cats: dict[str, int] = {}
    for r in records:
        cats[r.category] = cats.get(r.category, 0) + 1
    print(f"[ridb] wrote {n:,} records -> {OUT}")
    print(f"[ridb] categories: {dict(sorted(cats.items(), key=lambda kv: -kv[1]))}")
    print(f"[ridb] dropped: permit/ticket={dropped_permit} no_geo={dropped_nogeo} dup={dropped_dup}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
