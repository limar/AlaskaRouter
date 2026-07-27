---
# AlaskaRouter-o962
title: Map scale ignores the "Distances in miles" tweak (and the imperial ladder is wrong)
status: completed
type: bug
priority: high
created_at: 2026-07-27T21:33:50Z
updated_at: 2026-07-27T21:58:52Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. The on-map scale bar shows km even when the "Distances in miles" tweak is on.

## Two defects, one file — `AlaskaRouter/Map/ScaleIndicator.swift`

**1. Wrong source of truth (line 50)**
```swift
let imperial = Locale.current.measurementSystem == .us
```
Everything else in the app reads `TweaksStore.shared.distanceUnitIsMiles` (see `TweaksPanel.swift:64`, `TripBottomSheet.swift:869`, `RootView.swift:1391`). The scale is the one hold-out. It must read the tweak, and re-render when the tweak flips (the view takes `camera` as a plain `let`, so the observation wiring needs a look too).

**2. The imperial "nice numbers" ladder is in the wrong unit (lines 51-54)**
```swift
? [10, 25, 50, 100, 250, 500, 1000, 2500, 5280, 26400, 52800, ...]
```
These read as *feet* values but are compared against and divided by **meters**. `5280` is meant to be "1 mile" but is used as 5280 **m** = 3.28 mi, so the bar labels land on 3.3 mi / 16 mi / 33 mi instead of 1 / 5 / 10. The ladder has to be built in the display unit and converted to meters (`ft * 0.3048`, `mi * 1609.344`) before the `metersPerPixel` math.

## Todo
- [x] Read `TweaksStore.shared.distanceUnitIsMiles`; confirm the indicator re-renders on toggle
- [x] Rebuild the imperial ladder in ft/mi and convert to meters
- [x] Screenshot proof: same viewport, km vs mi, bar labels land on round numbers in both

## Summary of Changes

`ScaleIndicator` now reads `TweaksStore.shared.distanceUnitIsMiles` from inside `body`, so the @Observable store re-renders it when the tweak flips. `Locale.current.measurementSystem` is gone.

Both ladders rebuilt as display-unit values converted to meters via named `footInMeters` / `mileInMeters` constants, which also removes the 1609.34-vs-1609.344 mismatch `formatDistance` had. Both now extend to world zoom (10000 km / 6000 mi) instead of topping out at 500 km and collapsing to a 3 px bar when zoomed out.

**Verified on Simulator** at z7/z9/z11/z13, both units:

| zoom | before (mi) | after (mi) | after (km) |
|---|---|---|---|
| 7 | 16 mi | **25 mi** | 25 km |
| 11 | 1.6 mi | **1 mi** | 2.5 km |

The old ladder produced 3.3 / 16 / 33 / 98 / 328 / 820 / 3281 mi — every step a non-round number, exactly as the field report described.
