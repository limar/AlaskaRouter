---
# AlaskaRouter-0z7e
title: BIGTASK Universal map landmark clickability (cities, peaks, gas, lakes, …)
status: in-progress
type: epic
priority: high
created_at: 2026-05-19T07:59:29Z
updated_at: 2026-05-25T08:43:39Z
parent: AlaskaRouter-xtua
---




## Umbrella — "every visible thing is tappable, and you can add it to a trip"

Promoted from feature to epic (2026-05-25). Aggregates the work of making the map a first-class browsing surface, not just a route renderer. User's framing:

> "Show all known places on the map starting at some decently close zoom. All shown places should be clickable, showing a callout with basic info and an Add to Trip button. Any place on map should be clickable with a callout (showing the borough or even just AK, USA if that's Alaska) and '+' button. Currently mountain peaks are shown but in very small font."

## Architecture overview

```
       alaska-places.sqlite (33,470 entries, schema v4 with admin_area)
                        │
                        ▼
       build-time export: places.geojson (~5 MB, bundled)
                        │
       ┌────────────────┼─────────────────┐
       ▼                ▼                 ▼
   MLNShapeSource    Swift index for     (admin_area lookup
   "places"          runtime nearest-     reuses same data)
                     places search
       │
       ▼
   Multiple MLNSymbolStyleLayers — zoom-tiered + category-filtered:
     ┌──────────────────────────────────────────────────┐
     │ z=6+   settlement_major (Anchorage, Fairbanks)   │
     │ z=8+   settlement, airfield, visitor_center      │
     │ z=10+  peak (importance≥0.6), glacier, fuel, park│
     │ z=12+  lake, viewpoint, attraction, marina       │
     │ z=14+  everything else (camping, food, etc.)     │
     └──────────────────────────────────────────────────┘

   ExpeditionMapView.onTapMapGesture(on: placesLayerIDs ∪ tripLayerIDs)
        │
        ├─ features.first is a TRIP waypoint  → existing StopCallout flow
        ├─ features.first is a PLACE          → new PlacePreviewCallout
        └─ features empty (empty-map tap)     → new MapDropPinCallout
```

Three first-class callout types:

| Callout | Trigger | Shows |
|---|---|---|
| `StopCallout` (exists) | Tap on a trip waypoint marker | trip stop name, position N of M, Prev/Next/Remove |
| `PlacePreviewCallout` (new, ≈ PreviewCallout) | Tap on a place marker (settlement, peak, etc.) | place name, category, admin_area, "Add to trip" capsule |
| `MapDropPinCallout` (new) | Tap on empty map area | "Pin at 64.123, -149.456" + admin_area (runtime-resolved) + "Add to trip" |

## Children (under this epic)

- **AlaskaRouter-sn3r** — visual: hand-drawn circle-bullet markers (existing low-priority task, now reparented under this epic)
- **(NEW) Place-markers layer**: data prep + style + zoom-tiered visibility (subsumes "mountain peaks too small")
- **(NEW) Tap-on-place callout + add-to-trip**: PlacePreviewCallout, plumbing
- **(NEW) Tap-on-empty-map callout + add-to-trip**: MapDropPinCallout, runtime admin resolution

## Feasibility

- **MapLibre with 33k features in one MLNShapeSource:** known to work (we already do this conceptually for 13 anchor labels; same APIs scale). Performance budget worth verifying on device.
- **Zoom-tiered filtering** via `minzoom` on each layer + `filter` expressions on `importance` / `category`. All standard MapLibre style features.
- **Tap dispatch**: `.onTapMapGesture(on: layerIDs)` already used for trip waypoints. Just extend the layer-ID list.
- **Runtime nearest-place lookup** (for tap-on-empty-map): single bbox-filter + haversine pass over a pre-loaded array. ~1 ms per tap at 33k.
- **Bundle size**: places.geojson at ~5 MB compressed + alaska-places.sqlite (8.4 MB, can stay) = same data twice but the GeoJSON is for rendering, the SQLite is for search. Acceptable. Alternative: load GeoJSON FROM the SQLite at app launch on a background actor. Defer this optimization.

## Open architecture questions

1. **Bundle places.geojson, or generate from SQLite at launch?**
   - Bundle: +5 MB on-disk, zero app startup cost, simpler to debug.
   - Runtime-generate: no duplication on disk, ~50 ms launch cost.
   - **Recommendation: bundle.** Storage is cheap; launch latency matters.

2. **Visual treatment** of place markers:
   - (a) Generic colored dot per category (cheapest)
   - (b) Per-category SF Symbol icons baked at build time (richer; needs the WaypointIcons.swift pattern)
   - (c) Hand-drawn circle-bullets (sn3r — design-richer, hand-crafted SDF)
   - **Recommendation: (a) for the milestone, (c) as a follow-up once shipping.**

3. **Zoom tiers** — proposed above (z=6,8,10,12,14). **Confirm or tune.**

4. **Importance threshold** at each tier — proposed peaks ≥ 0.6 at z=10. **Confirm.**

5. **Label text below markers** — show always, or only at z=12+? **Recommendation: show always, MapLibre's `text-allow-overlap=false` will decimate at low zoom automatically.**

6. **Empty-map tap admin resolution** — bundle the GNIS donor subset as a small `place_admin_donors.json`, OR derive at runtime from the loaded places.geojson? **Recommendation: derive from already-loaded data — no extra bundle.**

7. **Existing `label-peak` style layer** (curated 13 anchor labels) — keep as a "named major peaks" headline tier with bigger font, or retire once the places layer carries peaks? **Recommendation: keep — it's the "atlas headline" tier (Brooks Range, Mount McKinley) and serves a different visual purpose.**

8. **OpenTopoMap raster peak labels** — these are baked-in pixels and will still show underneath our new vector layer. Visual clash possible at z=10+. **Plan: acknowledge, defer to 6ihk (self-render OTM) for true resolution.**

9. **Tap priority** when both a place marker AND a trip waypoint are stacked at the same coord — trip waypoint should win. **Recommendation: order layer IDs in the tap handler so trip waypoints are queried first.**

10. **Add-to-trip from callout** — use existing `SmartInsert.insertSmart` and the same `gxv0` workflow (keep search-bar / not, depending on state). **Confirm parity with search-result fast-add.**

## Out of scope (defer)

- Live filtering by category (toggle "peaks only" / "fuel only") — a future bean
- Place clustering at low zoom — MapLibre supports it natively; if needed, easy follow-up
- Multi-region (places.geojson per region pack) — comes with v2+ multi-region work

## Checklist

- [x] Lock the umbrella architecture (this body)
- [x] Reparent sn3r under this epic
- [ ] Lock the 10 open architecture questions (next AskUserQuestion / discussion turn)
- [ ] Place-markers child bean: data export + style layers
- [ ] Tap-on-place callout child bean
- [ ] Tap-on-empty-map callout child bean
- [ ] On-device verify
