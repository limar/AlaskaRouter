#!/usr/bin/env python3
"""List Copernicus GLO-30 DEM COG tiles for a configured render region."""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
from typing import NamedTuple


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "regions.json"
DEFAULT_BASE_URL = "https://copernicus-dem-30m.s3.amazonaws.com"


class DemCell(NamedTuple):
    lat: int
    lon: int

    @property
    def northing(self) -> str:
        prefix = "N" if self.lat >= 0 else "S"
        return f"{prefix}{abs(self.lat):02d}_00"

    @property
    def easting(self) -> str:
        prefix = "E" if self.lon >= 0 else "W"
        return f"{prefix}{abs(self.lon):03d}_00"

    @property
    def stem(self) -> str:
        return f"Copernicus_DSM_COG_10_{self.northing}_{self.easting}_DEM"

    @property
    def filename(self) -> str:
        return f"{self.stem}.tif"


def iter_dem_cells(bbox: list[float]):
    lon_min, lat_min, lon_max, lat_max = bbox
    for lat in range(math.floor(lat_min), math.ceil(lat_max)):
        for lon in range(math.floor(lon_min), math.ceil(lon_max)):
            yield DemCell(lat=lat, lon=lon)


def cell_url(base_url: str, cell: DemCell) -> str:
    base = base_url.rstrip("/")
    return f"{base}/{cell.stem}/{cell.filename}"


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("region_id")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--urls-only", action="store_true")
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    regions = json.loads(CONFIG.read_text())["regions"]
    if args.region_id not in regions:
        print(f"unknown region: {args.region_id}", file=sys.stderr)
        print("known regions:", ", ".join(sorted(regions)), file=sys.stderr)
        return 2

    cells = list(iter_dem_cells(regions[args.region_id]["bbox"]))
    if not args.urls_only:
        print(f"{args.region_id}: copernicus_glo30_cells={len(cells)}")
    for cell in cells:
        url = cell_url(args.base_url, cell)
        print(url if args.urls_only else f"{cell.filename} {url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
