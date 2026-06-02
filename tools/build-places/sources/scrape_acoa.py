#!/usr/bin/env python3
"""
Scrape the Alaska Campground Owners Association (ACOA) member directory for
private/commercial campgrounds & RV parks — the one category absent from the
federal/state/OSM sources. AlaskaRouter-rydj (scoped to ACOA only).

Source: https://akcampgrounds.com — a WordPress site. We read the
`acoa-member-list` page via the public wp-json REST API (cleaner than scraping
rendered HTML) and parse the "<Name> <street>, <City>, AK <zip>" entries, then
geocode each street address (cached Nominatim) into coordinates.

ROBOTS / TERMS: akcampgrounds.com/robots.txt allows User-agent:* (Allow: /)
and sets Content-Signal: search=yes (building a search index is permitted) /
ai-train=no (we do NOT train models on this). Our descriptive UA is not in the
blocked-bot list. This use — a local search gazetteer for trip planning — is a
search-index use, consistent with the site's stated terms. We make a single
REST read for the directory plus cached geocoding; no aggressive crawling.

Output: data/source-acoa.jsonl. Idempotent (skips if present; --force).

NOTE: this is a best-effort tertiary source. The member-list is an Elementor
text blob, so name/address extraction is heuristic; a couple of entries whose
NAME contains a comma may parse imperfectly. Coordinates are geocoded, so
treat positions as approximate (street-level where the address is clean, town-
level where it is a "Mile NN highway" address).
"""

from __future__ import annotations

import html as htmllib
import json
import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import DATA_DIR, SourceRecord, write_jsonl  # noqa: E402
from geocode import Geocoder  # noqa: E402

UA = {"User-Agent": "AlaskaRouter/0.1 (https://github.com/limar/AlaskaRouter; limar.go@gmail.com)"}
MEMBER_LIST = "https://akcampgrounds.com/wp-json/wp/v2/pages?slug=acoa-member-list"
ROBOTS = "https://akcampgrounds.com/robots.txt"
SOURCE = "acoa"
SOURCE_PAGE = "https://akcampgrounds.com/acoa-member-list/"
OUT = DATA_DIR / "source-acoa.jsonl"

ADDR_RE = re.compile(
    r'(.+?),\s*([A-Za-z .\'/-]+?),\s*AK\.?\s*(\d{5})(?:-\d{4})?', re.I)


def _fetch(url: str) -> str:
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def robots_allows() -> bool:
    """Verify User-agent:* is not Disallowed from / before we read anything."""
    try:
        body = _fetch(ROBOTS)
    except Exception as e:
        print(f"[acoa] could not fetch robots.txt ({e}) — refusing to proceed.")
        return False
    # Find the User-agent:* block and check for a blanket Disallow: /
    star = re.search(r'(?im)^user-agent:\s*\*\s*$(.*?)(?=^user-agent:|\Z)', body, re.S)
    block = star.group(1) if star else ""
    if re.search(r'(?im)^\s*disallow:\s*/\s*$', block):
        print("[acoa] robots.txt disallows '/' for *, refusing to scrape.")
        return False
    return True


def parse_entries(html: str) -> list[tuple[str, str]]:
    """Return [(name, full_address)] from the member-list page HTML."""
    html = re.sub(r'<(style|script)[^>]*>.*?</\1>', ' ', html, flags=re.S | re.I)
    html = re.sub(r'<[^>]+>', '\n', html)
    text = htmllib.unescape(html)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n+', '\n', text)
    out: list[tuple[str, str]] = []
    prev = 0
    for m in ADDR_RE.finditer(text):
        gap = text[prev:m.start()]
        lines = [l.strip() for l in gap.split('\n') if l.strip()]
        lines = [l for l in lines if not re.search(r'\bregion\b$', l, re.I)]
        name = lines[-1] if lines else ""
        street = m.group(1).strip().split('\n')[-1].strip()
        city, zp = m.group(2).strip(), m.group(3)
        prev = m.end()
        # Skip obvious parse fragments (continuation of a comma'd name).
        if len(name) < 4 or name.lower().startswith(("and ", "& ")):
            continue
        full = f"{street}, {city}, AK {zp}"
        out.append((name, full))
    return out


def main(argv: list[str]) -> int:
    force = "--force" in argv[1:]
    if OUT.exists() and OUT.stat().st_size > 0 and not force:
        n = sum(1 for _ in OUT.open())
        print(f"[skip] {OUT.name} present ({n:,} records). --force to refetch.")
        return 0
    if not robots_allows():
        return 1

    print("[acoa] reading member-list via wp-json...")
    pages = json.loads(_fetch(MEMBER_LIST))
    if not pages:
        raise SystemExit("[acoa] member-list page not found via wp-json")
    entries = parse_entries(pages[0]["content"]["rendered"])
    print(f"[acoa] parsed {len(entries)} name+address entries")

    geo = Geocoder()
    records: list[SourceRecord] = []
    seen: set[str] = set()
    no_geo = 0
    for name, addr in entries:
        if name in seen:
            continue
        seen.add(name)
        coord = geo.geocode(addr)
        if not coord:
            # fall back to "City, AK ZIP" (town-level) before giving up
            city_q = addr.split(",", 1)[1].strip() if "," in addr else addr
            coord = geo.geocode(city_q)
        if not coord:
            no_geo += 1
            print(f"[acoa]   no geocode: {name} ({addr})")
            continue
        records.append(SourceRecord(
            source=SOURCE, source_key=name, name=name,
            lat=coord[0], lon=coord[1], category="camping",
            booking_method="", source_url=SOURCE_PAGE,
        ))
    n = write_jsonl(records, OUT)
    print(f"[acoa] geocoder live calls: {geo.live_calls}")
    print(f"[acoa] wrote {n:,} records -> {OUT}  (no_geo={no_geo})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
