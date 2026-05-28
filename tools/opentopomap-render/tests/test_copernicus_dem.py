#!/usr/bin/env python3
"""Tests for Copernicus GLO-30 DEM planning and fetching."""

from __future__ import annotations

import contextlib
import http.server
import importlib.util
import pathlib
import tempfile
import threading
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PLAN_SCRIPT = ROOT / "scripts" / "plan-copernicus-dem.py"
FETCH_SCRIPT = ROOT / "scripts" / "fetch-copernicus-dem.py"
TIFF_BYTES = b"II*\x00fake-cog"


def load_script(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


@contextlib.contextmanager
def dem_server(missing_paths: set[str] | None = None):
    seen_paths: list[str] = []
    missing_paths = missing_paths or set()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            seen_paths.append(self.path)
            if self.path in missing_paths:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/tiff")
            self.end_headers()
            self.wfile.write(TIFF_BYTES)

        def log_message(self, format, *args):  # noqa: A002
            return

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/", seen_paths
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


class CopernicusDemTests(unittest.TestCase):
    def test_plans_copernicus_cells_for_alaska(self):
        planner = load_script(PLAN_SCRIPT, "plan_copernicus_dem")

        cells = list(planner.iter_dem_cells([-180.0, 51.0, -130.0, 72.0]))

        self.assertEqual(len(cells), 1050)
        self.assertEqual(cells[0].filename, "Copernicus_DSM_COG_10_N51_00_W180_00_DEM.tif")
        self.assertEqual(cells[-1].filename, "Copernicus_DSM_COG_10_N71_00_W131_00_DEM.tif")
        self.assertEqual(
            planner.cell_url("https://example.test/dem", cells[0]),
            "https://example.test/dem/"
            "Copernicus_DSM_COG_10_N51_00_W180_00_DEM/"
            "Copernicus_DSM_COG_10_N51_00_W180_00_DEM.tif",
        )

    def test_fetches_region_cells_from_configured_base_url(self):
        fetcher = load_script(FETCH_SCRIPT, "fetch_copernicus_dem")

        with tempfile.TemporaryDirectory() as tmp, dem_server() as (base_url, seen):
            rc = fetcher.main(
                [
                    "israel_palestine_poc",
                    "--base-url",
                    base_url,
                    "--output-dir",
                    tmp,
                    "--jobs",
                    "1",
                ]
            )

            self.assertEqual(rc, 0)
            self.assertEqual(len(seen), 15)
            self.assertTrue(
                seen[0].endswith(
                    "/Copernicus_DSM_COG_10_N29_00_E033_00_DEM/"
                    "Copernicus_DSM_COG_10_N29_00_E033_00_DEM.tif"
                )
            )
            self.assertEqual(
                (
                    pathlib.Path(tmp)
                    / "Copernicus_DSM_COG_10_N29_00_E033_00_DEM.tif"
                ).read_bytes(),
                TIFF_BYTES,
            )

    def test_missing_copernicus_cells_are_nonfatal_by_default(self):
        fetcher = load_script(FETCH_SCRIPT, "fetch_copernicus_dem")
        missing = (
            "/Copernicus_DSM_COG_10_N29_00_E033_00_DEM/"
            "Copernicus_DSM_COG_10_N29_00_E033_00_DEM.tif"
        )

        with tempfile.TemporaryDirectory() as tmp, dem_server({missing}) as (
            base_url,
            _seen,
        ):
            rc = fetcher.main(
                [
                    "israel_palestine_poc",
                    "--base-url",
                    base_url,
                    "--output-dir",
                    tmp,
                    "--jobs",
                    "1",
                ]
            )

            self.assertEqual(rc, 0)
            self.assertFalse(
                (
                    pathlib.Path(tmp)
                    / "Copernicus_DSM_COG_10_N29_00_E033_00_DEM.tif"
                ).exists()
            )


if __name__ == "__main__":
    unittest.main()
