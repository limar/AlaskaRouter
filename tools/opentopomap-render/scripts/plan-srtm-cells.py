#!/usr/bin/env python3
"""List SRTM-style HGT cells needed by a configured render region."""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
from typing import NamedTuple


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "regions.json"
SRTM_MIN_LAT = -56
SRTM_MAX_LAT = 60


class HgtCell(NamedTuple):
    lat: int
    lon: int
    name: str
    srtm_covered: bool


def hgt_name(lat: int, lon: int) -> str:
    lat_prefix = "N" if lat >= 0 else "S"
    lon_prefix = "E" if lon >= 0 else "W"
    return f"{lat_prefix}{abs(lat):02d}{lon_prefix}{abs(lon):03d}.hgt.zip"


def iter_hgt_cells(bbox: list[float]):
    lon_min, lat_min, lon_max, lat_max = bbox
    for lat in range(math.floor(lat_min), math.ceil(lat_max)):
        for lon in range(math.floor(lon_min), math.ceil(lon_max)):
            covered = SRTM_MIN_LAT <= lat < SRTM_MAX_LAT
            yield HgtCell(lat=lat, lon=lon, name=hgt_name(lat, lon), srtm_covered=covered)


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("region_id")
    ap.add_argument("--missing-only", action="store_true")
    ap.add_argument("--covered-only", action="store_true")
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.missing_only and args.covered_only:
        print("choose only one of --missing-only or --covered-only", file=sys.stderr)
        return 2

    regions = json.loads(CONFIG.read_text())["regions"]
    if args.region_id not in regions:
        print(f"unknown region: {args.region_id}", file=sys.stderr)
        print("known regions:", ", ".join(sorted(regions)), file=sys.stderr)
        return 2

    cells = list(iter_hgt_cells(regions[args.region_id]["bbox"]))
    covered = [cell for cell in cells if cell.srtm_covered]
    missing = [cell for cell in cells if not cell.srtm_covered]
    print(
        f"{args.region_id}: total={len(cells)} "
        f"srtm_covered={len(covered)} outside_srtm={len(missing)}"
    )

    selected = cells
    if args.covered_only:
        selected = covered
    elif args.missing_only:
        selected = missing

    for cell in selected:
        status = "srtm" if cell.srtm_covered else "outside-srtm"
        print(f"{cell.name} {status}")
    return 1 if missing and not (args.covered_only or args.missing_only) else 0


if __name__ == "__main__":
    raise SystemExit(main())
