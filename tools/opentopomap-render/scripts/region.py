#!/usr/bin/env python3
"""Read one field of a region from config/regions.json, for the Makefile.

The Makefile shells out to this so the pipeline never hard-codes a bbox/zoom:
    EXTENT := $(shell scripts/region.py $(REGION) extent)   # "minlon minlat maxlon maxlat"
    BBOX   := $(shell scripts/region.py $(REGION) bbox)     # "minlon,minlat,maxlon,maxlat"
    ZMAX   := $(shell scripts/region.py $(REGION) maxzoom)

Usage: region.py REGION FIELD
  FIELD in: extent | bbox | minzoom | maxzoom | zooms | geofabrik_url | title
Exits non-zero (so `make` stops) on an unknown region or field.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "regions.json"


def region(name):
    regions = json.loads(CONFIG.read_text()).get("regions", {})
    if name not in regions:
        sys.exit(f"region.py: unknown region {name!r} (have: {', '.join(sorted(regions))})")
    return regions[name]


def field(r, name):
    bbox = r["bbox"]
    zooms = r["zooms"]
    if name == "extent":
        return " ".join(str(v) for v in bbox)
    if name == "bbox":
        return ",".join(str(v) for v in bbox)
    if name == "minzoom":
        return str(min(zooms))
    if name == "maxzoom":
        return str(max(zooms))
    if name == "zooms":
        return " ".join(str(z) for z in zooms)
    if name in r:
        return str(r[name])
    sys.exit(f"region.py: unknown field {name!r}")


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: region.py REGION FIELD")
    print(field(region(argv[1]), argv[2]))


if __name__ == "__main__":
    main(sys.argv)
