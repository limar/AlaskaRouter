#!/usr/bin/env python3
"""Tests for contour PBF/XML validation."""

import contextlib
import importlib.util
import io
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
VALIDATE_SCRIPT = ROOT / "scripts" / "validate-contour-pbf.py"


def load_script(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def write_osm(path, way_refs):
    refs = "\n".join(f'    <nd ref="{ref}"/>' for ref in way_refs)
    path.write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
  <node id="1" lat="0" lon="0"/>
  <node id="2" lat="0" lon="0"/>
  <way id="100">
{refs}
  </way>
</osm>
""".format(refs=refs),
        encoding="utf-8",
    )


class ValidateContoursTests(unittest.TestCase):
    def test_accepts_small_way(self):
        validator = load_script(VALIDATE_SCRIPT, "validate_contour_pbf")

        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "small.osm"
            write_osm(path, [1, 2])
            stdout = io.StringIO()

            with contextlib.redirect_stdout(stdout):
                rc = validator.main([str(path), "--max-way-nodes", "2"])

        self.assertEqual(rc, 0)
        self.assertIn("max_way_nodes=2", stdout.getvalue())

    def test_rejects_oversized_way(self):
        validator = load_script(VALIDATE_SCRIPT, "validate_contour_pbf_oversized")

        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "large.osm"
            write_osm(path, [1, 2, 3])
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                rc = validator.main([str(path), "--max-way-nodes", "2"])

        self.assertEqual(rc, 1)
        self.assertIn("max way node count 3 exceeds 2", stderr.getvalue())

    def test_rejects_high_ids(self):
        validator = load_script(VALIDATE_SCRIPT, "validate_contour_pbf_high_id")

        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "high.osm"
            write_osm(path, [1, 2])
            path.write_text(path.read_text().replace('id="100"', 'id="300"'))
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                rc = validator.main([str(path), "--max-id", "200"])

        self.assertEqual(rc, 1)
        self.assertIn("way id 300 exceeds 200", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
