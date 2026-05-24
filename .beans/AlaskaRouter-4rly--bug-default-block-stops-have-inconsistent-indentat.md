---
# AlaskaRouter-4rly
title: 'Bug: default block stops have inconsistent indentation'
status: in-progress
type: bug
priority: high
created_at: 2026-05-24T15:58:44Z
updated_at: 2026-05-24T16:01:28Z
parent: AlaskaRouter-ka6b
---

User feedback (2026-05-24):
> minor problem with the default block display (can we align the logic so all the blocks behave uniformly and the "default" is no different in design and code?). When we add our first waypoints, the default block title appears BUT it's indented to the right (let's say one "tab") while the waypoints appear unindented. This is not the design and we see it instantly change when we add a separator manually - all the waypoints get indented (around two "tabs") relatively to the block titles.

## Root cause

\`TripBottomSheet.waypointRow\` has:

\`\`\`swift
let isIndented = !trip.separators.isEmpty
return HStack { ... }
    .padding(.leading, isIndented ? 22 : 4)
\`\`\`

So stops in a SINGLE-BLOCK trip (no separators) get 4 pt leading padding. The block header has 12 pt leading padding (from \`.padding(.horizontal, 12)\` in \`blockHeaderRow\`). So stops end up LESS indented than the header — visually wrong.

The conditional was a remnant of the implicit-first-block era — when block 0 had NO header, stops appearing flush-left looked right. Now that every block has a header (pufj), stops should always be indented under their header for uniform visual hierarchy.

## Fix

Drop the conditional. Set \`isIndented = true\` (or just hardcode the 22 pt). Block 0's stops will then sit 22 pt indented under its 12 pt header — same as block N's stops sit under block N's header.

## Checklist

- [ ] Change waypointRow's leading padding to always-22pt
- [ ] On-device verify (pending user check) single-block trip + multi-block trip render the same hierarchy


## Summary of Changes

`waypointRow` in `TripBottomSheet` previously used `let isIndented = !trip.separators.isEmpty` to conditionally pad stops 22 pt or 4 pt from the leading edge. The conditional was a remnant of the implicit-first-block era. With pufj making every block render a header (including block 0's synthetic one), the conditional produced inverted hierarchy in single-block trips: block 0's stops sat at 4 pt while its header sat at 12 pt.

Dropped the conditional. Stops now always have a 22 pt leading padding, sitting uniformly indented under their block header regardless of how many separators the trip has. Single-block and multi-block trips render with identical hierarchy.
