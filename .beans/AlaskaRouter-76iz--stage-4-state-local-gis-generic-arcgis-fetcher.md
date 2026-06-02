---
# AlaskaRouter-76iz
title: 'Stage 4 — State & local GIS: generic ArcGIS fetcher'
status: todo
type: task
priority: high
created_at: 2026-06-02T10:00:44Z
updated_at: 2026-06-02T10:01:05Z
parent: AlaskaRouter-ief3
blocked_by:
    - AlaskaRouter-l48r
---

sources/fetch_arcgis.py — keyless ArcGIS FeatureServer harvester driven by a small layer registry.

- [ ] Generic query: f=geojson, where=1=1, outFields=*, outSR=4326, paginated via resultOffset/resultRecordCount; fail loudly on HTTP error or unexpected schema.
- [ ] Layer registry (sources/arcgis_layers.py) with per-layer attribute mapping:
      - Alaska DNR 'State Park Boundary and Facility' facility layer (campgrounds, cabins, trailheads, boat launches).
      - BLM AK Recreation FeatureServer (gis.blm.gov/akarcgis .../BLM_AK_Recreation).
      - Kenai Peninsula Borough Campgrounds (gis.data.alaska.gov KPB::kpb-campgrounds).
- [ ] Polygon/line features => centroid (reuse feature_centroid logic). Keep non-camping facility types mapped to existing categories.
- [ ] Emit one data/source-<layer>.jsonl per layer; idempotent + --force.
- [ ] Acceptance: state/borough/BLM campgrounds + facilities ingested & deduped; spot-check Kenai + Chugach.
