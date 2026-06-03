#!/usr/bin/env python3
"""Tests for packing rendered XYZ tiles into MBTiles."""

import importlib.util
import pathlib
import sqlite3
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "pack-mbtiles.py"
PNG_1X1 = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01"
    b"\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe"
    b"\x02\xfeA\xe2&\xb1\x00\x00\x00\x00IEND\xaeB`\x82"
)


def load_packer():
    spec = importlib.util.spec_from_file_location("pack_mbtiles", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class PackMbtilesTests(unittest.TestCase):
    def test_packs_xyz_tiles_as_tms_mbtiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            tile = root / "tiles" / "3" / "4" / "3.png"
            tile.parent.mkdir(parents=True)
            tile.write_bytes(PNG_1X1)
            mbtiles = root / "out.mbtiles"

            packer = load_packer()
            with mock.patch("sys.argv", ["pack-mbtiles.py", "--tiles-dir", str(root / "tiles"), "--mbtiles", str(mbtiles)]):
                self.assertEqual(packer.main(), 0)

            db = sqlite3.connect(str(mbtiles))
            try:
                rows = db.execute("select zoom_level, tile_column, tile_row, tile_data from tiles").fetchall()
                metadata = dict(db.execute("select name, value from metadata"))
            finally:
                db.close()

            self.assertEqual(rows, [(3, 4, 4, PNG_1X1)])
            self.assertEqual(metadata["format"], "png")
            self.assertEqual(metadata["minzoom"], "3")
            self.assertEqual(metadata["maxzoom"], "3")

    def test_uses_string_path_for_sqlite_compatibility(self):
        packer = load_packer()
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "tiles").mkdir()
            mbtiles = root / "out.mbtiles"

            with mock.patch("sys.argv", ["pack-mbtiles.py", "--tiles-dir", str(root / "tiles"), "--mbtiles", str(mbtiles)]), mock.patch.object(packer.sqlite3, "connect") as connect:
                connect.return_value.executescript.return_value = None
                connect.return_value.execute.return_value = None
                connect.return_value.commit.return_value = None
                connect.return_value.close.return_value = None

                self.assertEqual(packer.main(), 0)

            self.assertEqual(connect.call_args[0], (str(mbtiles),))


if __name__ == "__main__":
    unittest.main()
