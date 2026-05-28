#!/usr/bin/env python3
"""Tests for exporting rendered tiles from a local OpenTopoMap server."""

from __future__ import annotations

import contextlib
import http.server
import importlib.util
import pathlib
import tempfile
import threading
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "export-region-tiles.py"
PNG_1X1 = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01"
    b"\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe"
    b"\x02\xfeA\xe2&\xb1\x00\x00\x00\x00IEND\xaeB`\x82"
)


def load_exporter():
    spec = importlib.util.spec_from_file_location("export_region_tiles", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


@contextlib.contextmanager
def tile_server():
    seen_paths: list[str] = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            seen_paths.append(self.path)
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.end_headers()
            self.wfile.write(PNG_1X1)

        def log_message(self, format, *args):  # noqa: A002
            return

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}", seen_paths
    finally:
        server.shutdown()
        thread.join()
        server.server_close()


class ExportRegionTilesTests(unittest.TestCase):
    def test_exports_region_to_packable_xyz_tree(self):
        exporter = load_exporter()

        with tempfile.TemporaryDirectory() as tmp, tile_server() as (base_url, seen):
            rc = exporter.main(
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
            exported = pathlib.Path(tmp) / "israel_palestine_poc" / "3" / "4" / "3.png"
            self.assertEqual(exported.read_bytes(), PNG_1X1)
            self.assertEqual(seen, ["/3/4/3.png"])

    def test_default_url_matches_otm_docker_tile_endpoint(self):
        exporter = load_exporter()

        self.assertEqual(
            exporter.tile_url("http://127.0.0.1:8080/otm", 3, 4, 3),
            "http://127.0.0.1:8080/otm/3/4/3.png",
        )


if __name__ == "__main__":
    unittest.main()
