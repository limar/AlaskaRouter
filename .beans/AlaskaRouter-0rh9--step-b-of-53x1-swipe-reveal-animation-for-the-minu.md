---
# AlaskaRouter-0rh9
title: 'Step B of 53x1: swipe-reveal animation for the minus button'
status: completed
type: task
priority: high
created_at: 2026-05-30T16:55:52Z
updated_at: 2026-05-30T17:43:13Z
parent: AlaskaRouter-e0vm
---

Second half of 53x1 (POSH minus + swipe-reveal). Build the custom reveal animation: tap minus → row content offsets left → red Delete trailing button reveals → tap Delete confirms, tap row body cancels. Companion to AlaskaRouter-4r06 (Step A: the minus button itself, already shipped in bed00d3).

## Approach (custom, NOT aheze/SwipeActions)
Aheze/SwipeActions inspected — large API surface (20+ modifiers, leading/trailing/multi-action), self-contained gesture system, no .onMove integration docs. Reorder-gesture conflict risk too high for our newly-stabilized List + .onMove + .onDelete setup. Rolling our own ~30 line custom version, taking inspiration from the spring values.

## Steps
- [ ] @State armedDeleteID: UUID? on TripBottomSheet — single value, so arming a new row automatically dismisses any other
- [ ] Restructure waypointRow as ZStack(alignment: .trailing) — red Delete on trailing layer + current row content on top with .offset
- [ ] Minus button: tap = arm (toggle); tap when armed = dismiss
- [ ] Row name Button: tap when armed = dismiss; tap when not armed = current onTapWaypoint behavior
- [ ] Red Delete button: tap = deleteWaypoint + dismiss
- [ ] Animation: .snappy(duration: 0.25) on the offset
- [ ] Apple's native .onDelete swipe path remains untouched
- [ ] Build + verify visually on simulator
- [ ] Test all gesture paths (tap minus / tap Delete / tap elsewhere / swipe / reorder still works)

## Future considerations
- Move-disable the armed row to prevent drag while in delete mode (deferred — let's see if it's actually awkward first)
- Auto-dismiss on scroll (deferred)

## Summary of Changes
Custom swipe-reveal animation for the minus button.

- @State armedDeleteID: UUID? on TripBottomSheet — single-value, arming a new row dismisses any other.
- waypointRow wrapped in ZStack(alignment: .trailing): row content as top layer with .offset(x: isArmed ? -84 : 0); behind it a Button(action: deleteWaypoint) whose width animates 0 → 84.
- Minus button: tap arms (or dismisses if already armed). Row body Button: tap dismisses when armed, otherwise calls onTapWaypoint.
- Animation: .snappy(duration: 0.25) on the ZStack, value armedDeleteID.
- Apple's native .onDelete swipe path untouched.
- Pill styling: Color(uiColor: .systemRed) + RoundedRectangle cornerRadius 10 + 4pt inset + SF Symbol trash.fill + Delete label, approximating the iOS system swipe-to-delete pill (close enough; corner/inset/sizes are educated guesses since Apple doesn't expose the exact tokens).
- Took two iterations to land: first attempt added .background(SheetPalette.cardFill) to the row HStack (broke translucency), second attempt's frame(width: 0) made the Text wrap character-by-character into 6 lines (rows grew to ~120pt). Final: fixedSize() on the Text inside an outer frame that animates the width, clipped() hiding overflow.
