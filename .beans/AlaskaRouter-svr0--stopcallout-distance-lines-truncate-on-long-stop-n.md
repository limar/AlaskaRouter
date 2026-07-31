---
# AlaskaRouter-svr0
title: StopCallout distance lines truncate on long stop names
status: completed
type: bug
priority: normal
created_at: 2026-07-31T22:12:24Z
updated_at: 2026-07-31T22:36:07Z
---

Split out of AlaskaRouter-dzhp (callout rework) on 2026-07-31, where it was spotted while verifying the title fix.

The stop callout's two distance lines name the *neighbouring* stops:

    132 km to Chena River Lakes Pr…

They carry `.lineLimit(1)`, so they hit the same long-Alaska-name problem the title just had — and worse, because the name they render is a whole other stop's, so a short stop can still truncate.

## Fix
**Let them wrap. No font-size change** (user's call — unlike the title, these are already the small secondary size and shrinking them further would make them unreadable).

Note the trap found in dzhp: `lineLimit` alone silently no-ops in this layout. Any wrapping needs `fixedSize(horizontal: false, vertical: true)`.

PreviewCallout's equivalent line already wraps (it has no `lineLimit`), so this is StopCallout only.

## Watch
The callout grows downward toward its pin. Measured in dzhp: a 2-line title leaves **~11pt** of clearance, and each extra line costs ~7.6pt. Adding wrapped distance lines eats into that, so re-measure the clearance after.

## Todo
- [x] Let the two distance lines wrap, with fixedSize
- [x] Verify on the real trip stop that truncated ("132 km to Chena River Lakes Project and Recreation Area")
- [x] Re-measure pin clearance now the callout is taller — **down to ~1-2pt, see below**

## Fixed (2026-07-31)

`.lineLimit(1)` dropped from both distance lines, `.fixedSize(horizontal: false, vertical: true)` added. Same 12pt, no shrink. Verified on the real trip: "132 km to Chena River Lakes Project and Recreation Area" now wraps to two lines and reads in full.

## Pin clearance is now ~1-2pt — flagged, not fixed

Measured on the real app at full res, both affected stops:
- before (dzhp, 2-line title): **~11pt** between the callout's bottom edge and the top of its pin
- now: **~1-2pt**. Adjacent, not overlapping — the pin is still fully visible — but there is no breathing room left.

The cause is structural. Both callouts are positioned `Spacer` / callout / `Spacer` / `Spacer` in RootView, i.e. centred on the upper third, so a taller callout grows **symmetrically** — half of every new line goes downward, toward the pin the map has centred beneath it.

**A stop with a long title AND two long neighbour names would overlap the pin.** Three extra lines ≈ 45pt of growth ≈ 22pt downward, against 1-2pt of clearance. Not present in the current trip, but reachable.

The fix, if wanted, is to stop growing symmetrically: anchor the callout's *bottom* a fixed distance above screen centre so growth goes upward, away from the pin. That is a change to how both callouts are positioned, so it wants a decision rather than a silent edit — raised with the user 2026-07-31.

## Two-line cap + the gap fixed (2026-07-31)

**Cap.** The distance lines are `lineLimit(2)`. Two covers every real neighbour name (the worst, "132 km to Chena River Lakes Project and Recreation Area", needs exactly two). The cap is a guard: user's point was that a deliberately absurd POI name should not be able to grow the card without limit.

**Gap.** New `CalloutSlot` in `AlaskaRouter/UI/CalloutSlot.swift`, used by both callouts.

The old placement was `Spacer` / callout / `Spacer` / `Spacer` — the card *centred* on the upper third, so every extra line pushed it half up and half **down**, toward the pin. That is why the clearance kept shrinking as the card learned to wrap.

Now the card's **bottom edge** is anchored a fixed distance above the pin, and extra lines grow upward into empty map. Verified on all three cases (short card, tall 2-line-title card, preview callout): the gap is now constant at roughly 22-35pt instead of collapsing to 1-2pt on the tall ones.

## Summary of Changes
1. Distance lines wrap instead of truncating, at the same 12pt, capped at two lines.
2. `CalloutSlot` anchors both callouts by their bottom edge, so card height no longer eats the pin clearance.
