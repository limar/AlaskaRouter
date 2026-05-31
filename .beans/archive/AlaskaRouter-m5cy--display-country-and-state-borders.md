---
# AlaskaRouter-m5cy
title: Display country and state borders
status: scrapped
type: feature
priority: normal
created_at: 2026-05-20T20:20:52Z
updated_at: 2026-05-21T15:11:55Z
parent: AlaskaRouter-xtua
---

Draw country and state administrative boundaries on the basemap. At low zoom the user sees the US/Canada border, Alaska's southern border with British Columbia, etc. — orientation cue that the current OpenTopoMap raster doesn't provide reliably at small scales. Style: thin dashed line, atlas convention.

## Why

Today the basemap (OpenTopoMap raster) is fine on terrain but quiet on political geography. At low/mid zoom there's no visible:
- US/Canada border (relevant for any Alaska–Yukon trip)
- Alaska state border with BC
- Maritime boundaries

Without these the user has no political orientation cue to pair with the topographic detail.

## Likely implementation

Vector source from Natural Earth's `ne_10m_admin_0_boundary_lines_land` (country) and `ne_10m_admin_1_states_provinces_lines` (state/province). Both are public domain, small (~few MB), and the standard atlas source.

Two `LineStyleLayer` entries:
- **Country border**: warm graphite `#3a3024`, `line-dasharray: [8, 3, 2, 3]` (long-short-short atlas convention), `line-width: ["interpolate", ["linear"], ["zoom"], 1, 0.7, 6, 1.4]`
- **State border**: same dasharray scaled tighter, lighter color, fade out around z=7 where local detail takes over

## Considerations

- Bundle size — Natural Earth 1:10m admin lines are ~4 MB combined; acceptable.
- v2+ generalization — when multi-region packs ship, borders stay in the world-skeleton portion (always bundled).
- Visual layering — borders should sit ABOVE raster but BELOW the route line and waypoints.

## Checklist

- [ ] Pull Natural Earth `admin_0_boundary_lines_land` + `admin_1_states_provinces_lines` (GeoJSON)
- [ ] Trim to relevant region for v1 (North America at minimum) to keep bundle small
- [ ] Add vector source + two LineStyleLayer entries to `style-base.json`
- [ ] Wire `__BORDERS_URL__` substitution in `ExpeditionMapView`
- [ ] Verify US/Canada border legible at z=3..6
- [ ] Verify route line still reads on top of border crossings
