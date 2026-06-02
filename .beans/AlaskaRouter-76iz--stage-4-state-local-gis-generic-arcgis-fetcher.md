---
# AlaskaRouter-76iz
title: 'Stage 4 — State & local GIS: generic ArcGIS fetcher'
status: completed
type: task
priority: high
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T12:18:44Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-l48r
---

sources/fetch_arcgis.py — keyless ArcGIS FeatureServer harvester driven by a small layer registry.

- [x] fetch_arcgis.py: f=geojson, where=1=1, outFields=*, outSR=4326, paginated via resultOffset (stop on short page). Fails loud on HTTP error and on ArcGIS error payloads. 429/5xx exponential backoff.
- [x] arcgis_layers.py: LayerSpec registry. Endpoints discovered: BLM gis.blm.gov/akarcgis .../BLM_AK_Recreation/FeatureServer (17 useful layers); DNR arcgis.dnr.alaska.gov .../DPOR/Park_Boundary_Facility/FeatureServer (layer 0 facilities = Cabin/Hut only + URL; layer 2 = 157 park-boundary polygons); KPB services.arcgis.com/ba4DH9pIcqkXJVfl .../KPB_Campgrounds_view/FeatureServer/0 (NAME+LINK). Category set per-layer (fixed) or per-feature (category_field+map, e.g. DNR FCLTYTYPE).
- [x] geojson_centroid() in common.py handles point/line/polygon/multi*. Non-camping kept: trailhead/boat_launch/viewpoint/attraction/visitor_center/ranger_station/airfield/picnic/cabin/hut/park all mapped. smart_title() moved to common.py (shared with RIDB).
- [x] Emits one file per SOURCE (better than per-layer): source-blm_ak.jsonl (201), source-ak_dnr_parks.jsonl (244), source-kpb.jsonl (83). Idempotent per source; --force, --source <name>. Also added CategoryLabel entries (cabin/trailhead/boat_launch/dump_station) — the Stage-1-deferred app labels, now that these categories exist.
- [x] Acceptance PASS: rebuild 33,662 -> 34,043 (+381). Surviving after dedup: DNR 201, BLM 174, KPB 54, RIDB 236. Camping rows 388 -> 468; cabins 0 -> 291. Spot-check Kenai: full KPB set (Skilak Lake, Bernice Lake, Cooper Creek...); DNR cabins carry dnr.alaska.gov pages.

## Summary of Changes

NEW sources/fetch_arcgis.py (generic keyless ArcGIS harvester) + sources/arcgis_layers.py (LayerSpec registry). Three sources, one JSONL each, merged via the data/source-*.jsonl glob.

- common.py: + smart_title() (moved from fetch_ridb, shared) and geojson_centroid().
- CategoryLabel.swift: + cabin/trailhead/boat_launch/dump_station labels (Stage-1-deferred; harmless until the v5 DB ships in Stage 6).

### Endpoints (probed 2026-06)
- BLM_AK_Recreation FeatureServer: 17 layers harvested (campgrounds, primitive campsites, reservable/free cabins, boat launches/ramps/takeouts, trailheads, overlooks, interpretive sites, visitor centers, offices, landing strips, + Recreation Area polygons). Uniform FET_NAME schema; no contact fields.
- DNR DPOR/Park_Boundary_Facility: facility points are Cabin/Hut ONLY (no campgrounds in that layer; 87 rows) but carry a real URL; + 157 ASP boundary polygons -> park (centroid).
- KPB_Campgrounds_view: 83 campground points (NAME + LINK).

Findings: BLM cabins layer-split by reservable/fee (booking_method set per layer: reservable->online_portal, free->no_reservations, primitive campsites->walk_in). DNR facility layer has NO state-park campgrounds (only cabins/huts) — those come from KPB/OSM/RIDB instead. Same importance-based merge caveat as Stage 3 (true source priority + field backfill = Stage 6). DB not yet swapped into Resources.
