---
# AlaskaRouter-p9xr
title: 'Bug: bottom sheet drag-to-detent jumps and rebounds'
status: completed
type: bug
priority: high
created_at: 2026-05-24T15:06:25Z
updated_at: 2026-05-29T14:43:11Z
parent: AlaskaRouter-ka6b
---

## Repro (iPhone 16)

1. Bottom sheet is at `.collapsed` (minimal, ~100 pt at the very bottom).
2. Drag it up with a finger to roughly the `.overview` (middle) position.
3. Release.

**Actual:** sheet visually JUMPS DOWN first, then animates BACK UP to the `.overview` position. Two-step animation, looks like a rebound. Same effect on any detent change via drag (collapsed→overview, overview→full, full→collapsed, etc).

**Expected:** sheet animates smoothly FROM the release position TO the target detent, in a single curve.

## Likely cause

`TripBottomSheet` uses `@GestureState private var dragOffset: CGFloat = 0` plus a computed `effectiveHeight = detent.height(in: geo.size.height) - dragOffset`. On gesture end:
1. `@GestureState` auto-resets `dragOffset` to 0 (its own implicit animation).
2. `detent` is set to the new value (its own animation via `withAnimation`).

These two animations don't perfectly cancel each other out. The visible jump-down-then-back-up is the gesture-reset running before the detent-move catches up.

## Fix direction

Two viable paths:
- (a) Replace `@GestureState` with `@State` and reset `dragOffset = 0` inside the same `withAnimation(...)` block where the new detent is set. Single combined animation.
- (b) Compute `effectiveHeight` from a `currentHeight: CGFloat` `@State` that's updated continuously during drag and set to the new detent's target on release. Drop the `targetHeight - dragOffset` arithmetic entirely.

(b) is cleaner — height becomes the source of truth, detents are just snap points.

## Checklist

- [ ] Read current TripBottomSheet drag-gesture implementation
- [ ] Pick fix path (a) or (b)
- [ ] Implement
- [ ] On-device verify smooth animation between all 3 detents
- [ ] Verify the new-trip / map gestures aren't disturbed


## Fix applied (2026-05-24)

`@GestureState private var dragOffset: CGFloat = 0` → `@State private var dragOffset: CGFloat = 0`.

`@GestureState` auto-resets to 0 the instant the drag gesture ends. That reset happened OUTSIDE the `withAnimation { detent = … }` block in `.onEnded`, so for one frame the sheet rendered at `targetHeight_old - 0` (its pre-drag detent height) before the detent's animation moved it to the new detent. That's the "jump down then back up" the user reported.

Switched to plain `@State`. In `.onEnded`, both `detent` and `dragOffset = 0` are now set INSIDE a single `withAnimation(.smooth(duration: 0.3))` block — SwiftUI animates the combined `targetHeight - dragOffset` expression smoothly from (old detent, current offset) to (new detent, 0) with no intermediate snap. Also switched `.updating($dragOffset)` to `.onChanged { dragOffset = … }` since we no longer need the gesture's automatic reset.

- [x] Read current TripBottomSheet drag-gesture implementation
- [x] Pick fix path (a) — @GestureState → @State with combined withAnimation
- [x] Implement
- [ ] On-device verify smooth animation between all 3 detents
- [ ] Verify the new-trip / map gestures aren't disturbed
