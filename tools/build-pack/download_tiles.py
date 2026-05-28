#!/usr/bin/env python3
"""Download OpenTopoMap raster tiles into an MBTiles SQLite database.

Resumable: tiles already in the DB are skipped. Parallel: small worker pool,
total throughput throttled to be polite to opentopomap.org (volunteer-run,
their usage policy asks for reasonable use + identifying User-Agent).

Plan for v1 'alaska-pack':
  - World skeleton z=0..5  (1365 tiles globally — continents/oceans/countries)
  - Alaska z=6..11         (statewide detail, bbox -180..-130 lon, 51..72 lat)
"""
import argparse
import math
import os
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

UA = "AlaskaRouter/v1 personal-use limar.go@gmail.com"
URL_TMPL = "https://tile.opentopomap.org/{z}/{x}/{y}.png"

ALASKA_BBOX = (-180.0, 51.0, -130.0, 72.0)  # (lon_min, lat_min, lon_max, lat_max)
WORLD_MAXZOOM = 5
ALASKA_MINZOOM = 6
ALASKA_MAXZOOM = 11


def lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    n = 2 ** z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    x = max(0, min(n - 1, x))
    y = max(0, min(n - 1, y))
    return x, y


def world_tiles(zooms: range) -> list[tuple[int, int, int]]:
    out = []
    for z in zooms:
        n = 2 ** z
        for x in range(n):
            for y in range(n):
                out.append((z, x, y))
    return out


def bbox_tiles(zooms: range, bbox: tuple[float, float, float, float]) -> list[tuple[int, int, int]]:
    lon_min, lat_min, lon_max, lat_max = bbox
    out = []
    for z in zooms:
        x_min, y_max = lonlat_to_tile(lon_min, lat_min, z)
        x_max, y_min = lonlat_to_tile(lon_max, lat_max, z)
        if x_min > x_max:
            x_min, x_max = x_max, x_min
        if y_min > y_max:
            y_min, y_max = y_max, y_min
        for x in range(x_min, x_max + 1):
            for y in range(y_min, y_max + 1):
                out.append((z, x, y))
    return out


def init_db(path: str, minzoom: int, maxzoom: int):
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS tiles (
            zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB,
            PRIMARY KEY(zoom_level, tile_column, tile_row)
        );
        PRAGMA journal_mode=WAL;
    """)
    meta = {
        "name": "AlaskaRouter alaska-pack",
        "format": "png",
        "type": "baselayer",
        "minzoom": str(minzoom),
        "maxzoom": str(maxzoom),
        "bounds": "-180,-85.0511,180,85.0511",
        "center": "-150,64,6",
        "attribution": "Map data © OpenStreetMap contributors, SRTM | Map style: © OpenTopoMap (CC-BY-SA)",
    }
    for k, v in meta.items():
        db.execute("INSERT OR REPLACE INTO metadata(name, value) VALUES(?,?)", (k, v))
    db.commit()
    db.close()


def count_existing_tiles(path: str) -> int:
    if not os.path.exists(path):
        return 0
    db = sqlite3.connect(path)
    count = db.execute("SELECT COUNT(*) FROM tiles").fetchone()[0]
    db.close()
    return int(count)


def existing_tiles(path: str) -> set[tuple[int, int, int]]:
    db = sqlite3.connect(path)
    rows = db.execute("SELECT zoom_level, tile_column, tile_row FROM tiles").fetchall()
    db.close()
    # We store TMS y in the DB. Convert back to XYZ y for set membership.
    out = set()
    for z, x, tms_y in rows:
        n = 2 ** z
        xyz_y = (n - 1) - tms_y
        out.add((z, x, xyz_y))
    return out


def fetch(z: int, x: int, y: int, timeout: float = 25.0) -> bytes | None:
    url = URL_TMPL.format(z=z, x=x, y=y)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = r.read()
            if not data or len(data) < 64:
                return None
            return data
    except urllib.error.HTTPError as e:
        if e.code in (404, 410):
            return b""  # sentinel: tile genuinely absent
        return None
    except Exception:
        return None


class Writer:
    """Single-thread DB writer fed from a queue of (z,x,y,data) results."""
    def __init__(self, path: str):
        self.path = path
        self.lock = threading.Lock()
        self.db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=NORMAL")
        self.pending = 0

    def write(self, z: int, x: int, y: int, data: bytes):
        n = 2 ** z
        tms_y = (n - 1) - y
        with self.lock:
            self.db.execute(
                "INSERT OR IGNORE INTO tiles(zoom_level,tile_column,tile_row,tile_data) VALUES(?,?,?,?)",
                (z, x, tms_y, data),
            )
            self.pending += 1
            if self.pending >= 200:
                self.db.execute("COMMIT").close() if False else None
                self.pending = 0

    def close(self):
        with self.lock:
            try:
                self.db.commit()
            except Exception:
                pass
            self.db.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--workers", type=int, default=2, help="parallel HTTP workers (be polite!)")
    ap.add_argument("--delay", type=float, default=0.45, help="per-worker delay between fetches (sec)")
    ap.add_argument("--phase", choices=["skeleton", "alaska", "both"], default="both")
    ap.add_argument("--world-maxzoom", type=int, default=WORLD_MAXZOOM)
    ap.add_argument("--alaska-minzoom", type=int, default=ALASKA_MINZOOM)
    ap.add_argument("--alaska-maxzoom", type=int, default=ALASKA_MAXZOOM)
    ap.add_argument("--dry-run", action="store_true", help="print target counts and exit without downloading")
    args = ap.parse_args()

    if args.world_maxzoom < 0:
        ap.error("--world-maxzoom must be >= 0")
    if args.alaska_minzoom < 0:
        ap.error("--alaska-minzoom must be >= 0")
    if args.alaska_maxzoom < args.alaska_minzoom:
        ap.error("--alaska-maxzoom must be >= --alaska-minzoom")

    maxzoom = max(args.world_maxzoom if args.phase in ("skeleton", "both") else 0,
                  args.alaska_maxzoom if args.phase in ("alaska", "both") else 0)
    init_db(args.db, 0, maxzoom)

    tiles: list[tuple[int, int, int]] = []
    if args.phase in ("skeleton", "both"):
        tiles += world_tiles(range(0, args.world_maxzoom + 1))
    if args.phase in ("alaska", "both"):
        tiles += bbox_tiles(range(args.alaska_minzoom, args.alaska_maxzoom + 1), ALASKA_BBOX)

    tiles = sorted(set(tiles))
    print(f"Total target tiles: {len(tiles)}")
    by_zoom: dict[int, int] = {}
    for z, _, _ in tiles:
        by_zoom[z] = by_zoom.get(z, 0) + 1
    print("Target tiles by zoom:")
    for z in sorted(by_zoom):
        print(f"  z={z}: {by_zoom[z]}")
    if args.dry_run:
        print(f"Existing rows in DB: {count_existing_tiles(args.db)}")
        return

    have = existing_tiles(args.db)
    todo = [t for t in tiles if t not in have]
    print(f"Already in DB: {len(have)}; remaining: {len(todo)}")
    if not todo:
        print("Nothing to do.")
        return

    writer = Writer(args.db)
    started = time.time()
    done = 0
    ok = 0
    miss = 0
    fail = 0
    lock = threading.Lock()

    def work(item):
        nonlocal done, ok, miss, fail
        z, x, y = item
        data = fetch(z, x, y)
        time.sleep(args.delay)  # per-worker politeness
        with lock:
            done += 1
            if data is None:
                fail += 1
            elif data == b"":
                miss += 1
            else:
                ok += 1
                writer.write(z, x, y, data)
            if done % 100 == 0 or done == len(todo):
                el = time.time() - started
                rate = done / max(el, 0.001)
                eta = (len(todo) - done) / max(rate, 0.001)
                print(f"[{time.strftime('%H:%M:%S')}] {done}/{len(todo)} ok={ok} miss={miss} fail={fail} "
                      f"rate={rate:.1f}/s eta={eta/60:.1f}min", flush=True)

    try:
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            for _ in as_completed([ex.submit(work, t) for t in todo]):
                pass
    finally:
        writer.close()

    print(f"\nFinished. ok={ok} miss={miss} fail={fail} (rerun to retry failed)")


if __name__ == "__main__":
    main()
