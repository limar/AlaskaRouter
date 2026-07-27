---
# AlaskaRouter-o962
title: Map scale ignores the "Distances in miles" tweak (and the imperial ladder is wrong)
status: todo
type: bug
priority: high
created_at: 2026-07-27T21:33:50Z
updated_at: 2026-07-27T21:36:47Z
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
- [ ] Read `TweaksStore.shared.distanceUnitIsMiles`; confirm the indicator re-renders on toggle
- [ ] Rebuild the imperial ladder in ft/mi and convert to meters
- [ ] Screenshot proof: same viewport, km vs mi, bar labels land on round numbers in both
