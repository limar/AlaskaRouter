#!/usr/bin/env python3
"""Fetch Copernicus GLO-30 DEM COG tiles for a configured render region."""

from __future__ import annotations

import argparse
import concurrent.futures
import importlib.util
import pathlib
import sys
import tempfile
import time
import urllib.error
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[1]
PLAN_SCRIPT = ROOT / "scripts" / "plan-copernicus-dem.py"
DEFAULT_OUTPUT = ROOT / "data" / "docker" / "data" / "copernicus-dem"
COG_SIGNATURES = (b"II*\x00", b"MM\x00*")


def load_planner():
    spec = importlib.util.spec_from_file_location("plan_copernicus_dem", PLAN_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def fetch_bytes(url: str, timeout: float) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "AlaskaRouter-dem-fetch/1"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        data = res.read()
    if not data.startswith(COG_SIGNATURES):
        raise ValueError(f"non-TIFF response from {url}")
    return data


def write_file(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
        tmp.write(data)
        tmp_path = pathlib.Path(tmp.name)
    tmp_path.replace(path)


def fetch_one(args) -> tuple[str, str, str | None]:
    cell, base_url, out_dir, force, retries, timeout, strict_missing = args
    path = out_dir / cell.filename
    if path.exists() and not force:
        return "skipped", cell.filename, None

    planner = load_planner()
    url = planner.cell_url(base_url, cell)
    last_error: Exception | None = None
    for attempt in range(retries + 1):
        try:
            write_file(path, fetch_bytes(url, timeout))
            return "written", cell.filename, None
        except urllib.error.HTTPError as exc:
            if exc.code == 404 and not strict_missing:
                exc.close()
                return "missing", cell.filename, "404 Not Found"
            last_error = exc
            if attempt < retries:
                time.sleep(min(5.0, 0.5 * (attempt + 1)))
        except (OSError, urllib.error.URLError, ValueError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(min(5.0, 0.5 * (attempt + 1)))

    return "failed", cell.filename, str(last_error)


def parse_args(argv: list[str]) -> argparse.Namespace:
    planner = load_planner()
    ap = argparse.ArgumentParser()
    ap.add_argument("region_id")
    ap.add_argument("--base-url", default=planner.DEFAULT_BASE_URL)
    ap.add_argument("--output-dir", default=str(DEFAULT_OUTPUT))
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--timeout", type=float, default=180.0)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--strict-missing", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    planner = load_planner()
    regions = planner.json.loads(planner.CONFIG.read_text())["regions"]
    if args.region_id not in regions:
        print(f"unknown region: {args.region_id}", file=sys.stderr)
        print("known regions:", ", ".join(sorted(regions)), file=sys.stderr)
        return 2

    cells = list(planner.iter_dem_cells(regions[args.region_id]["bbox"]))
    out_dir = pathlib.Path(args.output_dir)
    print(f"{args.region_id}: copernicus_glo30_cells={len(cells)}")
    if args.dry_run:
        for cell in cells:
            print(planner.cell_url(args.base_url, cell))
        print(f"output_dir={out_dir}")
        return 0

    tasks = [
        (
            cell,
            args.base_url,
            out_dir,
            args.force,
            args.retries,
            args.timeout,
            args.strict_missing,
        )
        for cell in cells
    ]
    written = skipped = missing = 0
    failures: list[tuple[str, str | None]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for status, filename, error in pool.map(fetch_one, tasks):
            if status == "written":
                written += 1
            elif status == "skipped":
                skipped += 1
            elif status == "missing":
                missing += 1
                print(f"missing {filename}: {error}", file=sys.stderr)
            else:
                failures.append((filename, error))

    print(
        f"written={written} skipped={skipped} "
        f"missing={missing} failed={len(failures)}"
    )
    for filename, error in failures[:20]:
        print(f"failed {filename}: {error}", file=sys.stderr)
    if len(failures) > 20:
        print(f"... {len(failures) - 20} more failures omitted", file=sys.stderr)
    return 1 if failures or (missing and args.strict_missing) else 0


if __name__ == "__main__":
    raise SystemExit(main())
