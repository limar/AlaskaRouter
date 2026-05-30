#!/usr/bin/env python3
"""Import generated contour PBFs into the OpenTopoMap contours database.

The upstream OpenTopoMap script imports every contour PBF in one osm2pgsql
process. Alaska's contour set is large enough to crash osm2pgsql 1.2 after the
process counter passes roughly two billion nodes, so this helper imports bounded
batches and records each successfully imported file for resumability.
"""

import argparse
import pathlib
import shlex
import shutil
import subprocess
import sys


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--srtm-dir",
        default="/mnt/data/srtm",
        type=pathlib.Path,
        help="Directory containing contour PBF files.",
    )
    parser.add_argument("--pattern", default="contour*.pbf")
    parser.add_argument("--database", default="contours")
    parser.add_argument("--owner", default="tirex")
    parser.add_argument("--style", default="/home/otm/db/contours.style")
    parser.add_argument("--cache", default="5000")
    parser.add_argument(
        "--batch-size",
        default=1,
        type=int,
        help="Maximum files per osm2pgsql invocation. Use >1 to reduce startup overhead.",
    )
    parser.add_argument(
        "--batch-max-bytes",
        default=0,
        type=int,
        help="Optional maximum total input bytes per batch. 0 disables the limit.",
    )
    parser.add_argument(
        "--flat-nodes",
        default=None,
        help="Optional osm2pgsql flat-nodes file path for slim node storage.",
    )
    parser.add_argument(
        "--state-dir",
        default=None,
        type=pathlib.Path,
        help="Directory for the imported-file marker. Defaults under --srtm-dir.",
    )
    parser.add_argument(
        "--recreate",
        action="store_true",
        help="Drop the contours database and clear import state before starting.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without executing them.",
    )
    return parser.parse_args(argv)


def quote(command):
    return " ".join(shlex.quote(part) for part in command)


def run(command, dry_run):
    print(quote(command), flush=True)
    if dry_run:
        return
    subprocess.run(command, check=True)


def database_exists(name):
    result = subprocess.run(
        ["psql", "-lqt"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )
    return any(line.split("|", 1)[0].strip() == name for line in result.stdout.splitlines())


def read_imported(marker):
    if not marker.exists():
        return set()
    return {line.strip() for line in marker.read_text().splitlines() if line.strip()}


def mark_imported(marker, filename, dry_run):
    print(f"# imported {filename}", flush=True)
    if dry_run:
        return
    with marker.open("a", encoding="utf-8") as file:
        file.write(f"{filename}\n")


def pending_files(files, imported):
    for path in files:
        if path.name in imported:
            print(f"# skip already imported {path.name}", flush=True)
            continue
        yield path


def file_size(path, dry_run):
    if dry_run:
        return 0
    return path.stat().st_size


def batches(paths, batch_size, batch_max_bytes, dry_run=False):
    if batch_size < 1:
        raise ValueError("--batch-size must be at least 1")
    if batch_max_bytes < 0:
        raise ValueError("--batch-max-bytes must not be negative")

    batch = []
    batch_bytes = 0
    for path in paths:
        size = file_size(path, dry_run)
        would_exceed_count = len(batch) >= batch_size
        would_exceed_bytes = (
            batch_max_bytes > 0 and batch and batch_bytes + size > batch_max_bytes
        )
        if would_exceed_count or would_exceed_bytes:
            yield batch
            batch = []
            batch_bytes = 0

        batch.append(path)
        batch_bytes += size

    if batch:
        yield batch


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    if args.batch_size < 1:
        print("--batch-size must be at least 1", file=sys.stderr)
        return 2
    if args.batch_max_bytes < 0:
        print("--batch-max-bytes must not be negative", file=sys.stderr)
        return 2

    srtm_dir = args.srtm_dir.resolve()
    state_dir = args.state_dir or srtm_dir / ".contour-import-state"
    marker = state_dir / f"{args.database}.imported"
    files = sorted(srtm_dir.glob(args.pattern))

    if not files:
        print(f"No {args.pattern} files found in {srtm_dir}", file=sys.stderr)
        return 1

    if args.recreate:
        run(["dropdb", "--if-exists", args.database], args.dry_run)
        if args.dry_run:
            print(f"rm -rf {shlex.quote(str(state_dir))}")
        elif state_dir.exists():
            shutil.rmtree(state_dir)

    if not args.dry_run:
        state_dir.mkdir(parents=True, exist_ok=True)

    if args.recreate or args.dry_run or not database_exists(args.database):
        run(["createdb", args.database, "-O", args.owner], args.dry_run)

    run(["psql", "-d", args.database, "-c", "CREATE EXTENSION IF NOT EXISTS postgis;"], args.dry_run)
    run(
        [
            "psql",
            "-d",
            args.database,
            "-c",
            "GRANT SELECT ON ALL TABLES IN SCHEMA public TO tirex;",
        ],
        args.dry_run,
    )

    imported = read_imported(marker)
    imported_count = len(imported)
    for batch in batches(
        pending_files(files, imported),
        args.batch_size,
        args.batch_max_bytes,
        args.dry_run,
    ):
        mode = "--create" if imported_count == 0 else "--append"
        command = [
            "osm2pgsql",
            mode,
            "--slim",
            "-d",
            args.database,
            "--cache",
            args.cache,
            "--style",
            args.style,
        ]
        if args.flat_nodes:
            command.extend(["--flat-nodes", args.flat_nodes])
        command.extend(str(path) for path in batch)
        run(command, args.dry_run)
        for path in batch:
            mark_imported(marker, path.name, args.dry_run)
            imported_count += 1

    run(
        [
            "psql",
            "-d",
            args.database,
            "-c",
            "GRANT SELECT ON ALL TABLES IN SCHEMA public TO tirex;",
        ],
        args.dry_run,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
