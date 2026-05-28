#!/usr/bin/env python3
"""Estimate XYZ tile targets for configured self-render regions."""

from __future__ import annotations

import json
import math
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "regions.json"


def lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[int, int]:
    n = 2**z
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return max(0, min(n - 1, x)), max(0, min(n - 1, y))


def bbox_tiles(bbox: list[float], zoom: int) -> tuple[int, int, int, int, int]:
    lon_min, lat_min, lon_max, lat_max = bbox
    x_min, y_max = lonlat_to_tile(lon_min, lat_min, zoom)
    x_max, y_min = lonlat_to_tile(lon_max, lat_max, zoom)
    if x_min > x_max:
        x_min, x_max = x_max, x_min
    if y_min > y_max:
        y_min, y_max = y_max, y_min
    count = (x_max - x_min + 1) * (y_max - y_min + 1)
    return x_min, x_max, y_min, y_max, count


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: estimate-region.py <region_id>", file=sys.stderr)
        return 2

    region_id = sys.argv[1]
    config = json.loads(CONFIG.read_text())
    regions = config["regions"]
    if region_id not in regions:
        print(f"unknown region: {region_id}", file=sys.stderr)
        print("known regions:", ", ".join(sorted(regions)), file=sys.stderr)
        return 2

    region = regions[region_id]
    total = 0
    print(f"{region_id}: {region['title']}")
    print(f"bbox: {region['bbox']}")
    for zoom in region["zooms"]:
        x_min, x_max, y_min, y_max, count = bbox_tiles(region["bbox"], zoom)
        total += count
        print(
            f"z={zoom}: x={x_min}..{x_max} y={y_min}..{y_max} "
            f"count={count}"
        )
    print(f"total={total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
