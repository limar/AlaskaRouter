#!/usr/bin/env python3
"""Print the Tirex command for pre-rendering a configured region."""

from __future__ import annotations

import json
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "regions.json"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: render-region-command.py <region_id>", file=sys.stderr)
        return 2

    region_id = sys.argv[1]
    regions = json.loads(CONFIG.read_text())["regions"]
    if region_id not in regions:
        print(f"unknown region: {region_id}", file=sys.stderr)
        return 2

    region = regions[region_id]
    bbox = ",".join(str(v) for v in region["bbox"])
    zooms = region["zooms"]
    if len(zooms) == 1:
        zoom_spec = str(zooms[0])
    else:
        zoom_spec = f"{min(zooms)}-{max(zooms)}"

    print(
        "tirex-batch -p ${OTM_RENDER_PROCESSES:-5} "
        f"-d map=opentopomap bbox={bbox} z={zoom_spec}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
