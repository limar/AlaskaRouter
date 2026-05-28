#!/usr/bin/env python3
"""Pack a rendered z/x/y.png tile tree into MBTiles.

Input layout:
  <tiles-dir>/<z>/<x>/<y>.png
"""

from __future__ import annotations

import argparse
import pathlib
import sqlite3


def iter_tiles(root: pathlib.Path):
    for path in sorted(root.glob("*/*/*.png")):
        z = int(path.parent.parent.name)
        x = int(path.parent.name)
        y = int(path.stem)
        yield z, x, y, path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles-dir", required=True)
    ap.add_argument("--mbtiles", required=True)
    ap.add_argument("--name", default="AlaskaRouter rendered tiles")
    ap.add_argument("--attribution", default="Map data © OpenStreetMap contributors, SRTM | Map style: © OpenTopoMap (CC-BY-SA)")
    args = ap.parse_args()

    tiles_dir = pathlib.Path(args.tiles_dir)
    out = pathlib.Path(args.mbtiles)
    out.parent.mkdir(parents=True, exist_ok=True)

    db = sqlite3.connect(out)
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS tiles (
            zoom_level INTEGER,
            tile_column INTEGER,
            tile_row INTEGER,
            tile_data BLOB,
            PRIMARY KEY(zoom_level, tile_column, tile_row)
        );
        DELETE FROM metadata;
        DELETE FROM tiles;
        """
    )

    count = 0
    minzoom: int | None = None
    maxzoom: int | None = None
    for z, x, y, path in iter_tiles(tiles_dir):
        n = 2**z
        tms_y = (n - 1) - y
        db.execute(
            "INSERT INTO tiles VALUES (?, ?, ?, ?)",
            (z, x, tms_y, path.read_bytes()),
        )
        count += 1
        minzoom = z if minzoom is None else min(minzoom, z)
        maxzoom = z if maxzoom is None else max(maxzoom, z)

    metadata = {
        "name": args.name,
        "type": "baselayer",
        "format": "png",
        "minzoom": str(minzoom or 0),
        "maxzoom": str(maxzoom or 0),
        "attribution": args.attribution,
    }
    for key, value in metadata.items():
        db.execute("INSERT INTO metadata VALUES (?, ?)", (key, value))
    db.commit()
    db.close()

    print(f"wrote {count} tiles to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
