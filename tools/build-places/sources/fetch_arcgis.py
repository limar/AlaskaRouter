#!/usr/bin/env python3
"""
Generic keyless ArcGIS REST harvester for the places DB (AlaskaRouter-76iz).

Reads the layer registry in arcgis_layers.py, queries each layer with
f=geojson&outSR=4326 (paginated via resultOffset), maps attributes into the
common SourceRecord shape, and writes one data/source-<source>.jsonl per
distinct source (BLM, DNR state parks, Kenai Peninsula Borough). No API key.

Fails LOUD on HTTP errors or an ArcGIS error payload (house rule: no silent
fallbacks). Idempotent per source: a source whose output file already exists is
skipped unless --force. --source <name> limits to one source.

Usage:
    sources/fetch_arcgis.py                  # all sources, skip existing
    sources/fetch_arcgis.py --force          # refetch all
    sources/fetch_arcgis.py --source kpb     # one source
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (  # noqa: E402
    DATA_DIR, SourceRecord, geojson_centroid, smart_title, write_jsonl,
)
from arcgis_layers import LAYERS, LayerSpec  # noqa: E402

UA = {"User-Agent": "AlaskaRouter/0.1 (https://github.com/limar/AlaskaRouter; limar.go@gmail.com)"}
PAGE = 1000


def _get(url: str, max_attempts: int = 5) -> dict:
    last = None
    for attempt in range(1, max_attempts + 1):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            last = e
            if e.code in (429, 500, 502, 503, 504):
                wait = int(e.headers.get("Retry-After", 0)) or min(60, 5 * 2 ** (attempt - 1))
                print(f"[arcgis] HTTP {e.code} — sleeping {wait}s ({attempt}/{max_attempts})")
                time.sleep(wait)
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:
            last = e
            wait = min(60, 5 * 2 ** (attempt - 1))
            print(f"[arcgis] {type(e).__name__}: {e} — sleeping {wait}s ({attempt}/{max_attempts})")
            time.sleep(wait)
    raise RuntimeError(f"ArcGIS request failed after {max_attempts} attempts: {last} ({url})")


def query_layer(spec: LayerSpec) -> list[dict]:
    """Page through one layer, returning all GeoJSON features."""
    feats: list[dict] = []
    offset = 0
    while True:
        params = urllib.parse.urlencode({
            "where": "1=1", "outFields": "*", "f": "geojson",
            "outSR": 4326, "resultOffset": offset, "resultRecordCount": PAGE,
        })
        url = f"{spec.service}/{spec.layer}/query?{params}"
        d = _get(url)
        if isinstance(d, dict) and d.get("error"):
            raise RuntimeError(f"ArcGIS error for {spec.source} layer {spec.layer}: {d['error']}")
        batch = d.get("features", [])
        feats.extend(batch)
        # A short page (or empty) means we've reached the end. Servers that
        # honor resultRecordCount return exactly PAGE while more remain.
        if len(batch) < PAGE:
            break
        offset += len(batch)
        time.sleep(0.2)
    return feats


def feature_to_record(feat: dict, spec: LayerSpec) -> SourceRecord | None:
    props = feat.get("properties") or {}
    name = smart_title(str(props.get(spec.name_field) or "").strip())
    if not name:
        return None
    # category
    if spec.category is not None:
        category = spec.category
    else:
        raw = str(props.get(spec.category_field) or "").strip()
        category = spec.category_map.get(raw)
        if not category:
            return None  # unmapped type — skip
    centroid = geojson_centroid(feat.get("geometry"))
    if not centroid:
        return None
    lat, lon = centroid
    if lat == 0.0 and lon == 0.0:
        return None
    url = ""
    if spec.url_field:
        url = str(props.get(spec.url_field) or "").strip()
    # source_key: stable per-feature id. Prefer a real id attr, else name+coord.
    oid = props.get("OBJECTID") or props.get("FID") or props.get("GlobalID")
    source_key = f"{spec.source}:{spec.layer}:{oid}" if oid else f"{spec.source}:{name}:{lat:.5f},{lon:.5f}"
    return SourceRecord(
        source=spec.source, source_key=source_key, name=name, lat=lat, lon=lon,
        category=category, booking_method=spec.booking_method,
        website=url, source_url=url,
    )


def main(argv: list[str]) -> int:
    args = argv[1:]
    force = "--force" in args
    only = None
    if "--source" in args:
        only = args[args.index("--source") + 1]

    # Group specs by source so we write one file per source.
    by_source: dict[str, list[LayerSpec]] = {}
    for spec in LAYERS:
        if only and spec.source != only:
            continue
        by_source.setdefault(spec.source, []).append(spec)
    if not by_source:
        raise SystemExit(f"no layers for --source {only!r}")

    for source, specs in by_source.items():
        out = DATA_DIR / f"source-{source}.jsonl"
        if out.exists() and out.stat().st_size > 0 and not force:
            n = sum(1 for _ in out.open())
            print(f"[skip] {out.name} present ({n:,} records). --force to refetch.")
            continue
        records: list[SourceRecord] = []
        seen: set[str] = set()
        per_cat: dict[str, int] = {}
        for spec in specs:
            feats = query_layer(spec)
            kept = 0
            for f in feats:
                rec = feature_to_record(f, spec)
                if rec is None or rec.source_key in seen:
                    continue
                seen.add(rec.source_key)
                records.append(rec)
                per_cat[rec.category] = per_cat.get(rec.category, 0) + 1
                kept += 1
            print(f"[arcgis] {source} layer {spec.layer} ({spec.label}): "
                  f"{len(feats)} feats -> {kept} kept")
        n = write_jsonl(records, out)
        print(f"[arcgis] wrote {n:,} -> {out}")
        print(f"[arcgis] {source} categories: {dict(sorted(per_cat.items(), key=lambda kv: -kv[1]))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
