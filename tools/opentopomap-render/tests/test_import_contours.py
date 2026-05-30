#!/usr/bin/env python3
"""Tests for chunked contour imports."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
IMPORT_SCRIPT = ROOT / "scripts" / "import-contours-in-chunks.py"


def load_script(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ImportContoursTests(unittest.TestCase):
    def test_dry_run_imports_first_file_with_create_then_appends(self):
        importer = load_script(IMPORT_SCRIPT, "import_contours_in_chunks")

        with tempfile.TemporaryDirectory() as tmp:
            srtm_dir = pathlib.Path(tmp)
            (srtm_dir / "contour-b.pbf").write_bytes(b"fake")
            (srtm_dir / "contour-a.pbf").write_bytes(b"fake")
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                rc = importer.main(["--srtm-dir", tmp, "--recreate", "--dry-run"])

        self.assertEqual(rc, 0)
        lines = output.getvalue().splitlines()
        self.assertIn("dropdb --if-exists contours", lines)
        self.assertIn("createdb contours -O tirex", lines)
        osm2pgsql_lines = [line for line in lines if line.startswith("osm2pgsql")]
        self.assertEqual(len(osm2pgsql_lines), 2)
        self.assertIn("--create", osm2pgsql_lines[0])
        self.assertIn("contour-a.pbf", osm2pgsql_lines[0])
        self.assertIn("--append", osm2pgsql_lines[1])
        self.assertIn("contour-b.pbf", osm2pgsql_lines[1])

    def test_dry_run_honors_file_pattern(self):
        importer = load_script(IMPORT_SCRIPT, "import_contours_in_chunks_pattern")

        with tempfile.TemporaryDirectory() as tmp:
            srtm_dir = pathlib.Path(tmp)
            (srtm_dir / "contour-poc.pbf").write_bytes(b"fake")
            (srtm_dir / "contour-warp-60_1_1.pbf").write_bytes(b"fake")
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                rc = importer.main(
                    [
                        "--srtm-dir",
                        tmp,
                        "--pattern",
                        "contour-warp-60_*.pbf",
                        "--dry-run",
                    ]
                )

        self.assertEqual(rc, 0)
        self.assertIn("contour-warp-60_1_1.pbf", output.getvalue())
        self.assertNotIn("contour-poc.pbf", output.getvalue())

    def test_dry_run_threads_flat_nodes_through_to_osm2pgsql(self):
        importer = load_script(IMPORT_SCRIPT, "import_contours_in_chunks_flat_nodes")

        with tempfile.TemporaryDirectory() as tmp:
            srtm_dir = pathlib.Path(tmp)
            (srtm_dir / "contour-a.pbf").write_bytes(b"fake")
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                rc = importer.main(
                    [
                        "--srtm-dir",
                        tmp,
                        "--dry-run",
                        "--flat-nodes",
                        "/mnt/db/contours-flat-nodes.bin",
                    ]
                )

        self.assertEqual(rc, 0)
        osm2pgsql_line = next(
            line for line in output.getvalue().splitlines() if line.startswith("osm2pgsql")
        )
        self.assertIn("--flat-nodes /mnt/db/contours-flat-nodes.bin", osm2pgsql_line)


if __name__ == "__main__":
    unittest.main()
