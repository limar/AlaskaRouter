#!/usr/bin/env python3
"""
Tiny cached Nominatim geocoder for the scraped-directory sources
(AlaskaRouter-rydj). Used to turn street addresses into coordinates.

Respects OSM Nominatim usage policy: descriptive User-Agent with contact, a
hard 1 request/second rate limit, and a persistent on-disk cache
(data/geocode-cache.json) so re-runs of the scrapers cost zero network for
addresses already resolved. Both hits and misses are cached (a miss is stored
as null) so we don't hammer the service re-asking for unfindable addresses;
delete the cache file (or the offending key) to retry.
"""

from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

from common import DATA_DIR

ENDPOINT = "https://nominatim.openstreetmap.org/search"
UA = {"User-Agent": "AlaskaRouter/0.1 (https://github.com/limar/AlaskaRouter; limar.go@gmail.com)"}
CACHE_PATH = DATA_DIR / "geocode-cache.json"
MIN_INTERVAL = 1.1  # seconds between live requests (policy: <= 1 req/s)


class Geocoder:
    def __init__(self, cache_path: Path = CACHE_PATH):
        self.cache_path = cache_path
        self.cache: dict[str, list[float] | None] = {}
        if cache_path.exists():
            self.cache = json.loads(cache_path.read_text(encoding="utf-8"))
        self._last = 0.0
        self.live_calls = 0

    def _save(self) -> None:
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        self.cache_path.write_text(
            json.dumps(self.cache, ensure_ascii=False, indent=0), encoding="utf-8")

    def geocode(self, query: str) -> tuple[float, float] | None:
        """Return (lat, lon) for an address query, or None. Cached."""
        key = " ".join(query.split()).strip()
        if not key:
            return None
        if key in self.cache:
            v = self.cache[key]
            return (v[0], v[1]) if v else None
        # rate limit
        dt = time.time() - self._last
        if dt < MIN_INTERVAL:
            time.sleep(MIN_INTERVAL - dt)
        params = urllib.parse.urlencode({
            "q": key, "format": "json", "limit": 1, "countrycodes": "us",
        })
        url = f"{ENDPOINT}?{params}"
        self._last = time.time()
        self.live_calls += 1
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                arr = json.loads(r.read().decode("utf-8"))
        except Exception as e:
            print(f"[geocode] error for {key!r}: {e}")
            arr = []
        result: list[float] | None = None
        if arr:
            try:
                result = [float(arr[0]["lat"]), float(arr[0]["lon"])]
            except (KeyError, ValueError):
                result = None
        self.cache[key] = result
        self._save()
        return (result[0], result[1]) if result else None


if __name__ == "__main__":
    import sys
    g = Geocoder()
    for q in sys.argv[1:]:
        print(q, "->", g.geocode(q))
