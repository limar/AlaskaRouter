#!/usr/bin/env python3
"""Fail fast on contour OSM/PBF files that are unsafe for osm2pgsql import."""

import argparse
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=pathlib.Path)
    parser.add_argument("--max-way-nodes", type=int, default=5000)
    parser.add_argument("--max-id", type=int, default=2000000000)
    parser.add_argument(
        "--max-id-span",
        type=int,
        default=None,
        help="Fail when a file's node or way ID span reaches this size.",
    )
    parser.add_argument(
        "--osmium",
        default="osmium",
        help="osmium executable used to stream PBF files as XML.",
    )
    return parser.parse_args(argv)


def open_osm_stream(path, osmium):
    suffixes = path.suffixes
    if path.suffix in {".osm", ".xml"} or suffixes[-2:] == [".osm", ".xml"]:
        return path.open("rb"), None

    process = subprocess.Popen(
        [osmium, "cat", "-f", "osm", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return process.stdout, process


def update_id_range(stats, key, raw_id):
    if raw_id is None:
        return
    try:
        value = int(raw_id)
    except ValueError:
        return
    minimum_key = f"{key}_min"
    maximum_key = f"{key}_max"
    stats[minimum_key] = value if stats[minimum_key] is None else min(stats[minimum_key], value)
    stats[maximum_key] = value if stats[maximum_key] is None else max(stats[maximum_key], value)


def scan_file(path, osmium):
    stats = {
        "path": str(path),
        "nodes": 0,
        "ways": 0,
        "max_way_nodes": 0,
        "max_way_id": None,
        "node_min": None,
        "node_max": None,
        "way_min": None,
        "way_max": None,
    }

    stream, process = open_osm_stream(path, osmium)
    if stream is None:
        raise RuntimeError(f"{path}: osmium did not provide an output stream")

    try:
        for _event, element in ET.iterparse(stream, events=("end",)):
            if element.tag == "node":
                stats["nodes"] += 1
                update_id_range(stats, "node", element.get("id"))
                element.clear()
                continue

            if element.tag == "way":
                stats["ways"] += 1
                update_id_range(stats, "way", element.get("id"))
                ref_count = sum(1 for child in element if child.tag == "nd")
                if ref_count > stats["max_way_nodes"]:
                    stats["max_way_nodes"] = ref_count
                    stats["max_way_id"] = element.get("id")
                element.clear()
    finally:
        stream.close()

    if process is not None:
        _stdout, stderr = process.communicate()
        if process.returncode != 0:
            raise RuntimeError(f"{path}: osmium failed: {stderr.decode('utf-8', 'replace')}")

    return stats


def id_span(stats, key):
    minimum = stats[f"{key}_min"]
    maximum = stats[f"{key}_max"]
    if minimum is None or maximum is None:
        return 0
    return maximum - minimum + 1


def validate(stats, args):
    errors = []
    if stats["max_way_nodes"] > args.max_way_nodes:
        errors.append(
            "max way node count "
            f"{stats['max_way_nodes']} exceeds {args.max_way_nodes} "
            f"(way id {stats['max_way_id']})"
        )

    for key in ("node", "way"):
        maximum = stats[f"{key}_max"]
        if maximum is not None and maximum > args.max_id:
            errors.append(f"{key} id {maximum} exceeds {args.max_id}")
        if args.max_id_span is not None and id_span(stats, key) >= args.max_id_span:
            errors.append(
                f"{key} id span {id_span(stats, key)} reaches {args.max_id_span}"
            )
    return errors


def print_stats(stats):
    print(
        "{path}: nodes={nodes} ways={ways} max_way_nodes={max_way_nodes} "
        "max_way_id={max_way_id} node_id_span={node_span} way_id_span={way_span}".format(
            node_span=id_span(stats, "node"),
            way_span=id_span(stats, "way"),
            **stats,
        )
    )


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    failed = False
    for path in args.paths:
        try:
            stats = scan_file(path, args.osmium)
        except Exception as exc:  # noqa: BLE001 - CLI should report all file failures.
            print(str(exc), file=sys.stderr)
            failed = True
            continue

        print_stats(stats)
        errors = validate(stats, args)
        for error in errors:
            print(f"{path}: {error}", file=sys.stderr)
        failed = failed or bool(errors)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
