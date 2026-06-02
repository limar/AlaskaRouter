#!/usr/bin/env python3
"""
Registry of ArcGIS REST layers to harvest for the places DB (AlaskaRouter-76iz).

Each LayerSpec describes one FeatureServer/MapServer layer and how to map its
attributes into the common SourceRecord shape. fetch_arcgis.py reads this and
writes one data/source-<source>.jsonl per distinct `source` (a source may span
several layers — e.g. BLM has ~14 point/polygon layers).

Category is set one of two ways:
  - `category`        : a fixed category for every feature in the layer
                        (used when the layer IS one type, e.g. BLM "Campground")
  - `category_field`  : a feature attribute whose value is looked up in
    + `category_map`    `category_map` (used when one layer mixes types, e.g.
                        DNR facilities with FCLTYTYPE in {Cabin, Hut}).
                        Unmapped values are skipped.

Optional:
  - `booking_method`  : fixed booking_method for the layer (validated)
  - `url_field`       : attribute carrying a real webpage -> website + source_url

Discovery notes (probed 2026-06, see bean): BLM layer schema is uniform
(FET_NAME/DESCRIPTION); DNR ASP facilities are Cabin/Hut only (no campgrounds
in that point layer) plus 157 park-boundary polygons; KPB is 83 campground
points with NAME + LINK.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class LayerSpec:
    source: str
    service: str            # FeatureServer/MapServer base URL (no trailing /layerid)
    layer: int
    name_field: str
    category: str | None = None
    category_field: str | None = None
    category_map: dict[str, str] = field(default_factory=dict)
    booking_method: str = ""
    url_field: str | None = None
    label: str = ""         # human note for logs


_BLM = "https://gis.blm.gov/akarcgis/rest/services/Recreation/BLM_AK_Recreation/FeatureServer"
_DNR = "https://arcgis.dnr.alaska.gov/arcgis/rest/services/DPOR/Park_Boundary_Facility/FeatureServer"
_KPB = "https://services.arcgis.com/ba4DH9pIcqkXJVfl/arcgis/rest/services/KPB_Campgrounds_view/FeatureServer"


LAYERS: list[LayerSpec] = [
    # ---- BLM Alaska Recreation (one category per layer; name=FET_NAME) -------
    LayerSpec("blm_ak", _BLM, 2,  "FET_NAME", category="airfield",      label="Landing Strip"),
    LayerSpec("blm_ak", _BLM, 3,  "FET_NAME", category="ranger_station", label="BLM Office"),
    LayerSpec("blm_ak", _BLM, 4,  "FET_NAME", category="boat_launch",   label="Boat Launch"),
    LayerSpec("blm_ak", _BLM, 5,  "FET_NAME", category="boat_launch",   label="Boat Ramp"),
    LayerSpec("blm_ak", _BLM, 6,  "FET_NAME", category="boat_launch",   label="Boat Takeout"),
    LayerSpec("blm_ak", _BLM, 7,  "FET_NAME", category="cabin", booking_method="no_reservations", label="Cabin (free)"),
    LayerSpec("blm_ak", _BLM, 8,  "FET_NAME", category="cabin", booking_method="online_portal",   label="Cabin (reservable)"),
    LayerSpec("blm_ak", _BLM, 9,  "FET_NAME", category="camping",       label="Campground"),
    LayerSpec("blm_ak", _BLM, 10, "FET_NAME", category="camping", booking_method="walk_in", label="Campsite (primitive)"),
    LayerSpec("blm_ak", _BLM, 11, "FET_NAME", category="attraction",    label="Interpretive Site"),
    LayerSpec("blm_ak", _BLM, 14, "FET_NAME", category="picnic",        label="Picnic Area"),
    LayerSpec("blm_ak", _BLM, 17, "FET_NAME", category="viewpoint",     label="Point of Interest"),
    LayerSpec("blm_ak", _BLM, 20, "FET_NAME", category="viewpoint",     label="Scenic Overlook"),
    LayerSpec("blm_ak", _BLM, 21, "FET_NAME", category="trailhead",     label="ATV Trailhead"),
    LayerSpec("blm_ak", _BLM, 22, "FET_NAME", category="trailhead",     label="Hiking Trailhead"),
    LayerSpec("blm_ak", _BLM, 23, "FET_NAME", category="visitor_center", label="Visitor Center"),
    LayerSpec("blm_ak", _BLM, 100, "FET_NAME", category="park",         label="Recreation Area (polygon)"),

    # ---- Alaska DNR State Parks ---------------------------------------------
    # Facility points: only Cabin/Hut present. URL is a real webpage.
    LayerSpec("ak_dnr_parks", _DNR, 0, "FACILITYNM",
              category_field="FCLTYTYPE",
              category_map={"Cabin": "cabin", "Hut": "hut"},
              url_field="URL", label="ASP Park Facilities"),
    # Park boundary polygons -> park (centroid).
    LayerSpec("ak_dnr_parks", _DNR, 2, "PARKNAME", category="park",
              label="ASP Boundary"),

    # ---- Kenai Peninsula Borough campgrounds --------------------------------
    LayerSpec("kpb", _KPB, 0, "NAME", category="camping",
              url_field="LINK", label="KPB Campgrounds"),
]
