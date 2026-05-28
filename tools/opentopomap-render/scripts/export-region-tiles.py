#!/usr/bin/env python3
"""Export rendered XYZ PNG tiles from a local OpenTopoMap HTTP server."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import pathlib
import sys
import tempfile
import time
import urllib.error
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "regions.json"
DEFAULT_OUTPUT = ROOT / "data" / "tiles"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    n = 2**z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return max(0, min(n - 1, x)), max(0, min(n - 1, y))


def iter_region_tiles(bbox: list[float], zooms: list[int]):
    lon_min, lat_min, lon_max, lat_max = bbox
    for z in zooms:
        x_min, y_max = lonlat_to_tile(lon_min, lat_min, z)
        x_max, y_min = lonlat_to_tile(lon_max, lat_max, z)
        if x_min > x_max:
            x_min, x_max = x_max, x_min
        if y_min > y_max:
            y_min, y_max = y_max, y_min
        for x in range(x_min, x_max + 1):
            for y in range(y_min, y_max + 1):
                yield z, x, y


def tile_url(base_url: str, z: int, x: int, y: int) -> str:
    return f"{base_url.rstrip('/')}/{z}/{x}/{y}.png"


def fetch_tile(url: str, timeout: float) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "AlaskaRouter-render-export/1"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        data = res.read()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"non-PNG response from {url}")
    return data


def write_tile(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
        tmp.write(data)
        tmp_path = pathlib.Path(tmp.name)
    tmp_path.replace(path)


def export_one(args) -> tuple[str, int, int, int, str | None]:
    z, x, y, base_url, out_root, force, retries, timeout = args
    path = out_root / str(z) / str(x) / f"{y}.png"
    if path.exists() and not force:
        return "skipped", z, x, y, None

    url = tile_url(base_url, z, x, y)
    last_error: Exception | None = None
    for attempt in range(retries + 1):
        try:
            write_tile(path, fetch_tile(url, timeout))
            return "written", z, x, y, None
        except (OSError, urllib.error.URLError, ValueError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(min(2.0, 0.25 * (attempt + 1)))

    return "failed", z, x, y, str(last_error)


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("region_id")
    ap.add_argument("--base-url", default="http://127.0.0.1:8080/otm")
    ap.add_argument("--output-dir", default=str(DEFAULT_OUTPUT))
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=30.0)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    regions = json.loads(CONFIG.read_text())["regions"]
    if args.region_id not in regions:
        print(f"unknown region: {args.region_id}", file=sys.stderr)
        print("known regions:", ", ".join(sorted(regions)), file=sys.stderr)
        return 2

    region = regions[args.region_id]
    tiles = list(iter_region_tiles(region["bbox"], region["zooms"]))
    out_root = pathlib.Path(args.output_dir) / args.region_id
    print(f"{args.region_id}: {len(tiles)} tiles -> {out_root}")
    if args.dry_run:
        return 0

    tasks = [
        (z, x, y, args.base_url, out_root, args.force, args.retries, args.timeout)
        for z, x, y in tiles
    ]
    written = skipped = 0
    failures: list[tuple[int, int, int, str | None]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for status, z, x, y, error in pool.map(export_one, tasks):
            if status == "written":
                written += 1
            elif status == "skipped":
                skipped += 1
            else:
                failures.append((z, x, y, error))

    print(f"written={written} skipped={skipped} failed={len(failures)}")
    for z, x, y, error in failures[:20]:
        print(f"failed {z}/{x}/{y}.png: {error}", file=sys.stderr)
    if len(failures) > 20:
        print(f"... {len(failures) - 20} more failures omitted", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
