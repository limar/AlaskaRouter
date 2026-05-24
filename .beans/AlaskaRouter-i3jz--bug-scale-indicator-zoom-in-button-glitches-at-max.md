---
# AlaskaRouter-i3jz
title: 'Bug: scale indicator + zoom-in button glitches at max zoom'
status: in-progress
type: bug
priority: high
created_at: 2026-05-24T15:06:25Z
updated_at: 2026-05-24T15:13:50Z
parent: AlaskaRouter-ka6b
---

## Repro (iPhone 16)

1. Pinch-zoom to maximum zoom (clamped by `TilePackManifest.effectiveMaxZoom`, working as designed).
2. Observe the scale indicator at the bottom-left — shows "5.0 km".
3. Tap the on-map "+" button repeatedly.

**Bugs:**
1. **Decimal-point formatting:** "5.0 km" should be "5 km". When the scale value is a whole number, the trailing `.0` is noise.
2. **Tap "+" at max zoom changes the scale indicator** (showing different scales as you keep tapping) even though the map itself doesn't visibly zoom further. The "+" button and the scale are out of sync with the map's actual clamped zoom.

**Expected:**
- Scale: show "5 km" (no decimal) for integer values; "1.5 km" or "0.5 km" for fractional only.
- "+" button at max zoom: either visually disabled with no action, OR a no-op. It must NOT update the scale display since the map's zoom isn't actually changing.

## Files

- `AlaskaRouter/Map/ScaleIndicator.swift` (number formatting)
- `AlaskaRouter/Map/MapControls.swift` (the +/- buttons)
- Likely `RootView.swift` / `ExpeditionMapView.swift` (how `mapCamera` zoom is plumbed)
- `AlaskaRouter/Map/TilePackManifest.swift` (`effectiveMaxZoom`)

## Checklist

- [ ] ScaleIndicator: strip trailing `.0` from whole-number scale values
- [ ] MapControls: clamp "+" to `effectiveMaxZoom` (and "-" to `0` or min). Either disable the button visually at the limit, or guard the action.
- [ ] Confirm scale recomputes from the map's *actual* current zoom, not from a separate optimistic counter
- [ ] On-device verify at max zoom: "+" doesn't change scale, "5 km" instead of "5.0 km"


## Fix applied (2026-05-24)

### Scale indicator: drop trailing `.0`

`ScaleIndicator.formatDistance` previously used `String(format: "%.1f km", km)` for the 1–10 km range, producing "5.0 km" for round values. Now routes through a `prettyOneDecimal(_:)` helper that returns `Int(rounded)` when the value is a whole number, `String(format: "%.1f", rounded)` otherwise. Same treatment applied to the 1–10 mi range.

### Zoom buttons: clamp to `effectiveMaxZoom`

`MapControls.adjustZoom` had a hardcoded `max(0, min(20, zoom + delta))` cap. The pinch gesture meanwhile respects `TilePackManifest.shared.effectiveMaxZoom` (set on `MLNMapView.maximumZoomLevel`). So tapping "+" past the actual max bumped the camera's local zoom past the map's clamp; the scale indicator (which reads `camera.state`) then computed a finer meters-per-pixel based on the inflated zoom, even though the map itself wasn't actually zooming.

Fix: clamp `adjustZoom` to `TilePackManifest.shared.effectiveMaxZoom` instead of the hardcoded 20. Also added a no-op early return when newZoom is essentially the current zoom (limit hit), and visual `.disabled` + 0.45 opacity on the +/- buttons when at the respective limit so the user sees the affordance gray out.

- [x] ScaleIndicator: strip trailing `.0` from whole-number scale values
- [x] MapControls: clamp `+` to `effectiveMaxZoom` and `-` to `0`. Visual disable on the button at the limit.
- [x] Confirm scale recomputes from the map's actual current zoom (camera.state now stays clamped)
- [ ] On-device verify at max zoom: "+" doesn't change scale, "5 km" instead of "5.0 km", button looks disabled
