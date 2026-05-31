---
# AlaskaRouter-4r8l
title: Tap-on-empty-map → drop-pin callout (admin info + add to trip)
status: completed
type: feature
priority: high
created_at: 2026-05-25T08:42:55Z
updated_at: 2026-05-29T14:40:45Z
parent: AlaskaRouter-0z7e
---

## Scope (child of AlaskaRouter-0z7e)

Tapping an EMPTY area of the map (no trip waypoint, no place marker within hit-tolerance) opens a callout showing:
- "Pin at {lat}, {lon}" or "Pin near {nearest place name}"
- admin_area resolved at runtime from the tap coord ("Denali, AK, USA" / "AK, USA" fallback)
- "+ Add to trip" capsule

## Design

- New `MapDropPinCallout` view (mostly mirrors `PreviewCallout` but for an unnamed location).
- Title: "Pin" or the nearest place name within e.g. 50 m (the marker is so close it's effectively here).
- Subtitle: admin_area string.
- Action: "+ Add to trip" creates an untitled waypoint at the tap coord via `SmartInsert.insertSmart`. The trip's waypoint label defaults to the admin_area or "Stop N".

## Runtime admin resolution

Same logic as `build_fts5.py`'s inheritance pass, ported to Swift:

```
nearest GNIS-sourced place within 30 km of tap → adopt its admin_area
no donor in range → "AK, USA" fallback
```

Donor list is the subset of places.geojson where `source = "gnis"` and `admin_area` non-empty. Load once on map appear. ~12 k donors. Bbox-prefilter + haversine on the surviving subset → <1 ms per tap.

## Checklist

- [ ] Wire empty-area tap (features empty branch in onTapMapGesture)
- [ ] Runtime nearest-donor lookup helper
- [ ] MapDropPinCallout view
- [ ] "+" → SmartInsert with admin_area or "Stop N" as label
- [ ] On-device verify


## Summary of Changes

Wired the empty-area tap to drop a pin with admin-area lookup. iOS Maps convention: tap dismisses any open overlay first; a second tap on truly empty terrain drops a pin.

### Files

- **`AdminAreaLookup.swift`** (new) — runtime port of build_fts5.py's pass 2c. On launch, parses `places.geojson` on a background task, filters to `source = "gnis"` rows with non-empty `admin_area` (~12 k donors), buckets them by integer-degree latitude. `nearestAdmin(for: coord)` does a bbox-banded haversine search and returns the admin string within 30 km, or `""` if none. ~200 ms parse, sub-ms lookup, ~500 KB memory.
- **`ExpeditionMapView.swift`** — new `onEmptyMapTap: ((CLLocationCoordinate2D) -> Void)?` callback; the empty branch of the tap-gesture now fires this with `context.coordinate` instead of the old `onWaypointTap(nil)`. `onWaypointTap` is now non-Optional UUID (only fires on real waypoint hits).
- **`RootView.swift`**:
  - `handleMapEmptyTap(_:)` — dismiss-first behavior: if search active / preview open / waypoint selected → dismiss that one thing (highest priority each) and return. Otherwise drop a pin: synthesize a `SearchResult` named "Dropped pin", `category=""` (falls back to default `mappin.circle.fill` icon), `adminArea` resolved at runtime, assign to `previewedResult`. Existing `PreviewCallout` renders with "+ Add to trip"; "+" routes through `handleAddPreviewed` → `SmartInsert.insertSmart`.
  - `handleMapWaypointTap(_:)` simplified — `id` is now non-optional; the empty branch is gone.
  - Pre-warmed `AdminAreaLookup.shared.startLoad()` in the root `.onAppear` so the first drop-pin tap doesn't pay the parse cost.
- **`PreviewCallout.swift`** — new admin-area line (`"{adminArea}, AK, USA"` or `"AK, USA"` fallback). Benefits all three preview cases: search-result preview, place-tap (5gmw), drop-pin (4r8l).

### Behavior

- **Tap empty terrain (nothing open):** Dropped-pin callout appears, shows the lat/lon + the resolved borough ("Denali, AK, USA" / "Yukon-Koyukuk, AK, USA" / "AK, USA" if no donor in range). Tap "+ Add to trip" → SmartInsert adds the waypoint.
- **Tap empty terrain (search active):** Dismisses search.
- **Tap empty terrain (preview open):** Dismisses the preview.
- **Tap empty terrain (waypoint selected):** Dismisses the selection / StopCallout.

### Checklist

- [x] `AdminAreaLookup` Swift port of pass-2c with background parse
- [x] `onEmptyMapTap` callback wired in `onTapMapGesture` empty branch
- [x] `handleMapEmptyTap` dismiss-first + drop-pin behavior
- [x] `PreviewCallout` shows admin area on its own line
- [x] Pre-warm on `.onAppear`
- [ ] On-device verify: tap empty area drops a pin, "+" adds waypoint; dismiss-first works for each open-overlay case
