#!/usr/bin/env python3
"""Tests for fetching SRTM HGT ZIP files for render regions."""

from __future__ import annotations

import contextlib
import http.server
import importlib.util
import pathlib
import tempfile
import threading
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "fetch-srtm.py"
ZIP_BYTES = b"PK\x03\x04fake-hgt-zip"


def load_fetcher():
    spec = importlib.util.spec_from_file_location("fetch_srtm", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


@contextlib.contextmanager
def srtm_server(missing_paths: set[str] | None = None):
    seen_paths: list[str] = []
    missing_paths = missing_paths or set()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            seen_paths.append(self.path)
            if self.path in missing_paths:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.end_headers()
            self.wfile.write(ZIP_BYTES)

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


class FetchSrtmTests(unittest.TestCase):
    def test_fetches_region_cells_from_configured_base_url(self):
        fetcher = load_fetcher()

        with tempfile.TemporaryDirectory() as tmp, srtm_server() as (base_url, seen):
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
            self.assertIn("/N29E033.SRTMGL1.hgt.zip", seen)
            self.assertIn("/N33E035.SRTMGL1.hgt.zip", seen)
            self.assertEqual(
                (pathlib.Path(tmp) / "N29E033.SRTMGL1.hgt.zip").read_bytes(),
                ZIP_BYTES,
            )

    def test_missing_cells_are_nonfatal_by_default(self):
        fetcher = load_fetcher()

        with tempfile.TemporaryDirectory() as tmp, srtm_server(
            {"/N29E033.SRTMGL1.hgt.zip"}
        ) as (base_url, _seen):
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
            self.assertFalse((pathlib.Path(tmp) / "N29E033.SRTMGL1.hgt.zip").exists())

    def test_refuses_regions_outside_standard_srtm_coverage(self):
        fetcher = load_fetcher()

        with tempfile.TemporaryDirectory() as tmp:
            rc = fetcher.main(["alaska_z11", "--output-dir", tmp, "--dry-run"])

        self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main()
