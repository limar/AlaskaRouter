---
# AlaskaRouter-4r8l
title: Tap-on-empty-map → drop-pin callout (admin info + add to trip)
status: todo
type: feature
priority: high
created_at: 2026-05-25T08:42:55Z
updated_at: 2026-05-25T08:42:55Z
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
