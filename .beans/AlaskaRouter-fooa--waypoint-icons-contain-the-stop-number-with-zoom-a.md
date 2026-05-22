---
# AlaskaRouter-fooa
title: Waypoint icons contain the stop number (with zoom-aware legibility floor)
status: todo
type: feature
priority: high
created_at: 2026-05-20T19:42:55Z
updated_at: 2026-05-21T15:13:00Z
parent: AlaskaRouter-xtua
blocked_by:
    - AlaskaRouter-h82l
---

Bake the stop number into the waypoint marker icon so users can read each waypoint's position-in-trip directly from the map. Heavily related to h82l (waypoint icons scale with zoom): when zoom-scaling pushes icons below a legible threshold, the number fades and only the bare disc + ring remains.

## What the user wants

Each waypoint icon on the map shows the stop's index — the same number that appears on the row in the bottom sheet ("1" Cantwell, "2" Denali Park Entrance, ...). Numbers are inside the icon. They stay visible until zoom-out shrinks the icon below the threshold where digits can fit; below that, the icon degrades gracefully to just the disc + ring (matching whatever h82l's degraded-icon mode looks like).

## Why

Visual orientation between the sheet and the map. Today the only correspondence between "stop #3 in my list" and "which dot on the map" is by relative position — easy to mis-count on a dense route. With numbers in the icons, the user looks at the sheet, finds "Healy = 3", and immediately spots dot "3" on the map.

This mirrors the white-fill-stroke-with-tabular-digit pip we just shipped in the bottom sheet redesign (9634) — same visual idiom, on-map.

## Relationship to h82l

Heavily related. h82l (waypoint icons scale with zoom; degrade to dots at low zoom) is the **prerequisite** for the zoom-aware legibility floor — h82l decides at which zoom the icon becomes too small for any text. fooa just inherits that threshold and uses it as the number's fade-out point.

Implementation order: h82l first, fooa second. fooa is marked blocked-by h82l.

## Likely implementation

`AlaskaRouter/Map/WaypointIcons.swift` is the icon factory (UIGraphicsImageRenderer-based PNGs). Today it produces one bitmap per style. Two paths:

### (a) Pre-rendered per-number bitmaps (simpler)
Render N icons up front (one per stop index), each with the digit baked in. Trip waypoints reference `WaypointIcons.numbered(wp.order + 1)`. Cap N at ~99; bigger trips fall back to non-numbered.
- Pros: zero runtime cost, simple symbol-layer wiring.
- Cons: bitmap per stop, can't smoothly fade the digit independently of the disc.

### (b) Two-layer rendering (more elegant)
Keep the existing disc/ring bitmap. Add a SymbolStyleLayer with `text-field: ["to-string", ["get", "stopNumber"]]` reading from each waypoint feature's properties, placed at the same anchor with `text-anchor: center`. Fade with `text-opacity` interpolation tied to zoom.
- Pros: digit fade-out is a single style expression; no per-stop bitmap.
- Cons: needs adding `stopNumber` to the trip-marker GeoJSON feature properties; needs Noto Sans glyphs at the right size range (already bundled).

**Recommendation: (b)**. It composes naturally with h82l's icon-scale interpolation; the digit gets its own opacity ramp and just fades when icons reach the legibility floor.

## Checklist

- [ ] Wait on h82l to land (the icon-scale ramp determines the digit fade-out zoom)
- [ ] Add `stopNumber` to the trip-marker feature properties in `ExpeditionMapView`
- [ ] Add a `SymbolStyleLayer` on top of the marker layer with `text-field` + zoom-tied opacity
- [ ] Tune font size + halo to read against both default and selected icon styles
- [ ] Verify fade-out at the threshold matches the icon's "too small for a digit" point
- [ ] Visual side-by-side with the bottom sheet — same number, same trip, same dot

## Open question

For stops with index >= 10 (two digits), does the icon need to grow slightly to keep digit density readable, or do we just accept tighter digits? Probably the latter for v1; revisit if it bugs.

## References

- `AlaskaRouter/Map/WaypointIcons.swift` — icon factory
- `AlaskaRouter/Map/ExpeditionMapView.swift` (~line 159) — `iconImage(WaypointIcons.committedDefault)`
- AlaskaRouter-h82l — prerequisite (icon zoom-scaling + low-zoom degradation)
- AlaskaRouter-9634 — sheet redesign with the same numbered-pip idiom
