#!/usr/bin/env python3
"""Tests for planning SRTM HGT cells for render regions."""

from __future__ import annotations

import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "plan-srtm-cells.py"


def load_planner():
    spec = importlib.util.spec_from_file_location("plan_srtm_cells", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class PlanSrtmCellsTests(unittest.TestCase):
    def test_names_hgt_cells_for_low_latitude_poc(self):
        planner = load_planner()

        cells = list(planner.iter_hgt_cells([33.9, 29.3, 36.0, 33.4]))

        self.assertEqual(len(cells), 15)
        self.assertEqual(cells[0].name, "N29E033.hgt.zip")
        self.assertEqual(cells[-1].name, "N33E035.hgt.zip")
        self.assertTrue(all(cell.srtm_covered for cell in cells))

    def test_flags_alaska_cells_north_of_srtm_coverage(self):
        planner = load_planner()

        cells = list(planner.iter_hgt_cells([-180.0, 51.0, -130.0, 72.0]))

        covered = [cell for cell in cells if cell.srtm_covered]
        missing = [cell for cell in cells if not cell.srtm_covered]
        self.assertEqual(len(cells), 1050)
        self.assertEqual(len(covered), 450)
        self.assertEqual(len(missing), 600)
        self.assertEqual(missing[0].name, "N60W180.hgt.zip")


if __name__ == "__main__":
    unittest.main()
