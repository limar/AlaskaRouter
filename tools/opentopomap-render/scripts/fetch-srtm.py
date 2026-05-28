#!/usr/bin/env python3
"""Fetch SRTMGL1 HGT ZIP files for a configured render region."""

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
from typing import NamedTuple


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "regions.json"
DEFAULT_OUTPUT = ROOT / "data" / "docker" / "data" / "srtm"
DEFAULT_BASE_URL = "https://step.esa.int/auxdata/dem/SRTMGL1/"
SRTM_MIN_LAT = -56
SRTM_MAX_LAT = 60
ZIP_SIGNATURE = b"PK\x03\x04"


class HgtCell(NamedTuple):
    lat: int
    lon: int
    srtm_covered: bool

    @property
    def stem(self) -> str:
        lat_prefix = "N" if self.lat >= 0 else "S"
        lon_prefix = "E" if self.lon >= 0 else "W"
        return f"{lat_prefix}{abs(self.lat):02d}{lon_prefix}{abs(self.lon):03d}"

    @property
    def filename(self) -> str:
        return f"{self.stem}.SRTMGL1.hgt.zip"


def iter_hgt_cells(bbox: list[float]):
    lon_min, lat_min, lon_max, lat_max = bbox
    for lat in range(math.floor(lat_min), math.ceil(lat_max)):
        for lon in range(math.floor(lon_min), math.ceil(lon_max)):
            yield HgtCell(
                lat=lat,
                lon=lon,
                srtm_covered=SRTM_MIN_LAT <= lat < SRTM_MAX_LAT,
            )


def cell_url(base_url: str, cell: HgtCell) -> str:
    return f"{base_url.rstrip('/')}/{cell.filename}"


def fetch_bytes(url: str, timeout: float) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "AlaskaRouter-srtm-fetch/1"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        data = res.read()
    if not data.startswith(ZIP_SIGNATURE):
        raise ValueError(f"non-ZIP response from {url}")
    return data


def write_file(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
        tmp.write(data)
        tmp_path = pathlib.Path(tmp.name)
    tmp_path.replace(path)


def fetch_one(args) -> tuple[str, str, str | None]:
    cell, base_url, out_dir, force, retries, timeout = args
    out_path = out_dir / cell.filename
    if out_path.exists() and not force:
        return "skipped", cell.filename, None

    url = cell_url(base_url, cell)
    last_error: Exception | None = None
    for attempt in range(retries + 1):
        try:
            write_file(out_path, fetch_bytes(url, timeout))
            return "written", cell.filename, None
        except (OSError, urllib.error.URLError, ValueError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(min(2.0, 0.25 * (attempt + 1)))

    return "failed", cell.filename, str(last_error)


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("region_id")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--output-dir", default=str(DEFAULT_OUTPUT))
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=120.0)
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

    cells = list(iter_hgt_cells(regions[args.region_id]["bbox"]))
    missing = [cell for cell in cells if not cell.srtm_covered]
    print(
        f"{args.region_id}: total={len(cells)} "
        f"srtm_covered={len(cells) - len(missing)} outside_srtm={len(missing)}"
    )
    if missing:
        print(
            "region has cells outside standard SRTM coverage; choose a "
            "high-latitude DEM source first",
            file=sys.stderr,
        )
        for cell in missing[:20]:
            print(f"outside SRTM: {cell.stem}", file=sys.stderr)
        if len(missing) > 20:
            print(f"... {len(missing) - 20} more omitted", file=sys.stderr)
        return 1

    out_dir = pathlib.Path(args.output_dir)
    if args.dry_run:
        for cell in cells:
            print(cell_url(args.base_url, cell))
        print(f"output_dir={out_dir}")
        return 0

    tasks = [
        (cell, args.base_url, out_dir, args.force, args.retries, args.timeout)
        for cell in cells
    ]
    written = skipped = 0
    failures: list[tuple[str, str | None]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for status, filename, error in pool.map(fetch_one, tasks):
            if status == "written":
                written += 1
            elif status == "skipped":
                skipped += 1
            else:
                failures.append((filename, error))

    print(f"written={written} skipped={skipped} failed={len(failures)}")
    for filename, error in failures[:20]:
        print(f"failed {filename}: {error}", file=sys.stderr)
    if len(failures) > 20:
        print(f"... {len(failures) - 20} more failures omitted", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
