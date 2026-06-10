import json
import subprocess
import sys
import tempfile
import unittest
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
REGION_PY = ROOT / "scripts" / "region.py"


def run(*args, config=None):
    env = None
    return subprocess.run(
        [sys.executable, str(REGION_PY), *args],
        capture_output=True, text=True, env=env,
    )


class TestRegion(unittest.TestCase):
    def test_real_config_alaska(self):
        # The committed config must expose alaska_z11 with a sane bbox/zoom.
        out = run("alaska_z11", "bbox")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.strip(), "-180.0,51.0,-130.0,72.0")
        self.assertEqual(run("alaska_z11", "extent").stdout.strip(),
                         "-180.0 51.0 -130.0 72.0")
        self.assertEqual(run("alaska_z11", "maxzoom").stdout.strip(), "11")
        self.assertEqual(run("alaska_z11", "minzoom").stdout.strip(), "11")

    def test_unknown_region_fails(self):
        out = run("nope_z99", "bbox")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("unknown region", out.stderr)

    def test_unknown_field_fails(self):
        out = run("alaska_z11", "wat")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("unknown field", out.stderr)

    def test_fields_from_synthetic_config(self):
        # Drive the field logic directly against a synthetic region dict.
        sys.path.insert(0, str(ROOT / "scripts"))
        import region as R
        r = {"bbox": [-10, 20, 30, 40], "zooms": [6, 7, 8], "title": "T",
             "geofabrik_url": "http://x"}
        self.assertEqual(R.field(r, "extent"), "-10 20 30 40")
        self.assertEqual(R.field(r, "bbox"), "-10,20,30,40")
        self.assertEqual(R.field(r, "minzoom"), "6")
        self.assertEqual(R.field(r, "maxzoom"), "8")
        self.assertEqual(R.field(r, "zooms"), "6 7 8")
        self.assertEqual(R.field(r, "geofabrik_url"), "http://x")


if __name__ == "__main__":
    unittest.main()
