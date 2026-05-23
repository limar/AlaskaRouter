#!/usr/bin/env python3
"""
Fetch Alaska-located Wikidata items with coordinates.

AlaskaRouter-22h7 step 5: Wikidata fills the long tail of culturally /
historically named places that aren't in either OSM (businesses-and-
landmarks) or USGS GNIS (US-government natural-feature names). Examples:
ghost towns, indigenous communities, museums, named historic sites,
items with multilingual names.

Query: items transitively located in Alaska (Q797) with coordinates (P625).
Output: data/wikidata-ak.jsonl (one item per line; qid, name, lat, lon, types).

Idempotent: skips when the .jsonl already exists. Delete the file to refetch.
Wikidata's etiquette requires a descriptive User-Agent. Single query takes
~60–120 s against WDQS.
"""

from __future__ import annotations

import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = (
    "AlaskaRouter/0.1 (https://github.com/limar/AlaskaRouter; "
    "limar.go@gmail.com)"
)
OUT = Path(__file__).resolve().parent / "data" / "wikidata-ak.jsonl"

# Raw query — one row per (item, coord, type) tuple. P131* is transitive
# "located in admin entity" — anything in any sub-region of Alaska (boroughs,
# census areas, settlements inside Alaska) is included. Most items have a
# single coord+type, so 21.6k items produces ~24k rows. We dedupe in Python
# (cheaper than SPARQL GROUP_CONCAT/SAMPLE — those time out at WDQS's 60s
# hard limit for a 20k+ item set).
QUERY = """
SELECT ?item ?itemLabel ?lat ?lon ?typeLabel WHERE {
  ?item wdt:P131* wd:Q797 .
  ?item wdt:P625 ?coord .
  BIND(geof:latitude(?coord)  AS ?lat)
  BIND(geof:longitude(?coord) AS ?lon)
  OPTIONAL {
    ?item wdt:P31 ?type .
    ?type rdfs:label ?typeLabel . FILTER(LANG(?typeLabel) = "en")
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""


def fetch(query: str, timeout: int = 240, max_attempts: int = 5) -> dict:
    """Hit WDQS once. Respects 429 by sleeping at least Retry-After
    seconds (or 90s default) before the next attempt. WDQS sometimes
    enforces an "1 request / minute" cap during outages — that's why
    the default backoff is generous."""
    params = urllib.parse.urlencode({"query": query, "format": "json"})
    url = ENDPOINT + "?" + params
    last_err = None
    for attempt in range(1, max_attempts + 1):
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "application/sparql-results+json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                # strict=False tolerates control chars inside string values —
                # Wikidata labels sometimes carry stray ones (e.g. NBSP or
                # vertical-tab in Russian/Inupiaq native names).
                return json.loads(resp.read().decode("utf-8"), strict=False)
        except urllib.error.HTTPError as e:
            last_err = e
            if e.code == 429:
                wait = int(e.headers.get("Retry-After", "90"))
                wait = max(wait, 70)        # WDQS minimum is 1 req/min
                print(f"[wikidata] HTTP 429 — sleeping {wait}s "
                      f"(attempt {attempt}/{max_attempts})")
                time.sleep(wait)
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = e
            wait = 30 * attempt
            print(f"[wikidata] {type(e).__name__}: {e} — sleeping {wait}s "
                  f"(attempt {attempt}/{max_attempts})")
            time.sleep(wait)
    raise RuntimeError(f"WDQS failed after {max_attempts} attempts: {last_err}")


def main() -> int:
    if OUT.exists() and OUT.stat().st_size > 0:
        n = sum(1 for _ in OUT.open())
        print(f"[skip] {OUT.name} already present ({n:,} items)")
        return 0
    print("[wikidata] fetching all Alaska items with coords (60-120 s)...")
    t0 = time.time()
    try:
        data = fetch(QUERY)
    except Exception as e:
        print(f"[wikidata] ERROR: {e}", file=sys.stderr)
        return 1
    dt = time.time() - t0
    rows = data["results"]["bindings"]
    print(f"[wikidata] {len(rows):,} rows in {dt:.1f}s")

    # Aggregate rows in Python: one record per qid, with first-seen coord
    # and a deduped " | "-joined list of type labels.
    items: dict[str, dict] = {}
    skipped_unlabeled = 0
    skipped_bad_coord = 0
    for b in rows:
        qid = b["item"]["value"].rsplit("/", 1)[-1]
        name = b.get("itemLabel", {}).get("value", "")
        # When wikibase:label can't find an English label it falls back
        # to the qid (e.g. "Q1234567") — skip those.
        if not name or name == qid:
            skipped_unlabeled += 1
            continue
        rec = items.get(qid)
        if rec is None:
            try:
                lat = float(b["lat"]["value"])
                lon = float(b["lon"]["value"])
            except (KeyError, ValueError):
                skipped_bad_coord += 1
                continue
            rec = {"qid": qid, "name": name, "lat": lat, "lon": lon,
                   "types_set": set()}
            items[qid] = rec
        tlab = b.get("typeLabel", {}).get("value", "")
        if tlab:
            rec["types_set"].add(tlab)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as f:
        for rec in items.values():
            f.write(json.dumps({
                "qid":   rec["qid"],
                "name":  rec["name"],
                "lat":   rec["lat"],
                "lon":   rec["lon"],
                "types": " | ".join(sorted(rec["types_set"])),
            }, ensure_ascii=False) + "\n")
    print(f"[wikidata] kept={len(items):,}  unlabeled={skipped_unlabeled:,}  "
          f"bad_coords={skipped_bad_coord:,}")
    print(f"[wikidata] wrote {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
