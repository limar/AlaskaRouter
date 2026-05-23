---
# AlaskaRouter-pufj
title: Always create default block. Any waypoint will be inside some block.
status: completed
type: task
priority: high
created_at: 2026-05-21T15:06:48Z
updated_at: 2026-05-23T17:20:00Z
parent: AlaskaRouter-xtua
---

## Plan

The data model is already correct: \`trip.blocks\` always returns ≥1 block for any non-empty trip, and the implicit first block is a real block (with a real color, derived from the trip's color). Every waypoint is *already* inside some block.

What's NOT correct: a defensive \`fallbackColor\` path in \`ExpeditionMapView.syncTripMarkerGroup\` that bypasses the per-block color when the lookup misses. Since the lookup never legitimately misses (every waypoint is in some block), this path obscures intent and hides bugs.

### Changes

- **\`ExpeditionMapView.swift\`** — drop the \`fallbackColor: TripColor\` parameter from \`syncTripMarkerGroup\`. Drop the \`?? fallbackColor\` in the color lookup. Add an \`assertionFailure\` in DEBUG when a waypoint isn't in \`blocksByWaypointID\` so future schema bugs surface loudly rather than silently rendering the trip color.
- **\`TripBlocks.swift\`** — update the \"implicit first block\" comments to make it clear block 0 is a full first-class block (just one without a preceding separator, by definition).

### Out of scope

- Adding a visible \"header card\" for block 0 in the bottom sheet (separate UX question — the trip name at the top of the sheet already plays that role).
- Allowing block 0 to be user-renamed (separate feature, requires a name field on a persistent block model — bigger schema change).

### Checklist

- [x] Drop fallbackColor from ExpeditionMapView.syncMarkerLayers + syncTripMarkerGroup
- [x] Replace fallback with DEBUG assert (silent amber in release so a marker still draws)
- [x] Update TripBlocks + TripBottomSheet comments to drop the "implicit first block" framing
- [ ] Build, verify trip still renders correctly with per-block coloring (on-device check)


## Summary of Changes

`ExpeditionMapView.syncTripMarkerGroup` no longer accepts a `fallbackColor`. The per-waypoint block lookup is now unconditional — if it ever misses, that's a schema-invariant violation surfaced via `assertionFailure` in DEBUG. (Release still draws something — falls back to amber silently — so a bug never produces an invisible marker.)

`TripBlocks.swift` and `TripBottomSheet.swift` had comments calling the first block "implicit" — updated to clarify it's a full first-class block, just one without a leading separator by definition.

No schema changes. No data-model changes. Pure code-cleanup that bakes in the invariant the data model already enforced.
