---
# AlaskaRouter-ijy9
title: Lock / archive a trip (read-only, memory-safe)
status: completed
type: feature
priority: normal
created_at: 2026-07-27T22:41:21Z
updated_at: 2026-07-31T23:12:22Z
parent: AlaskaRouter-36of
---

From the Alaska field trip, July 2026. Finished trips are memories. Right now nothing stops an accidental drag, swipe-delete or smart-insert from quietly rewriting one.

## What is wanted
A way to mark a trip read-only — "locked", "archived", or similar — so it can be opened and admired but not edited by accident.

## To decide
- **Lock vs archive — are these one feature or two?** Lock = still in the active list, just not editable. Archive = moved out of the main list into a separate section, implying lock. The trip switcher already exists (AlaskaRouter-7k2b), so archive has somewhere to go.
- What exactly is frozen? Waypoints and blocks clearly. What about the *routing* — should a locked trip still refresh pendingSnap legs when the network returns (AlaskaRouter-2l0i / the pendingSnap auto-refresh design)? Recomputing geometry is arguably not "editing", and a locked trip with permanently dashed legs would be a sad memento.
- How is it unlocked, and how obvious should that be? Too easy and it doesn't protect; too hidden and it's annoying.
- Does a locked trip show any on-map or in-sheet indicator?

## Notes
Touches every mutation path in `TripBottomSheet` (reorder, swipe-remove, add separator) plus `SmartInsert` and the callout add/remove actions — the guard wants to live in one place (TripStore or the model) rather than being sprinkled across the UI.

## Decisions (2026-07-31, user)

- **Lock only, not archive.** A locked trip stays in the normal list; nothing is hidden away or moved.
- **Routing keeps refreshing.** Locked freezes the *itinerary* — stops, order, separators — not the drawn line. A leg that fell back to a straight dashed line offline still becomes a real road when the network returns. That changes how the trip is drawn, not what it is.
- **Locking** lives in the trip "…" menu, next to Rename. **Unlocking** is the badge, with a confirmation.
- **In the list, the edit controls disappear** rather than greying out. **On the map, the add buttons grey out** rather than disappearing — a vanished button reads as a bug, a dimmed one says "not right now, and here's what would do it".

## Summary of Changes

- `Trip.isLocked` (defaulted, so SwiftData migrates without a versioned step) + `TripStore.setLocked`. Renaming stays allowed on a locked trip: it does not touch the itinerary, and being unable to fix a typo would annoy without protecting anything.
- **Bottom sheet**: 6-dot drag handles, ⊖ buttons and "+ Split here" chips are gone when locked; `onMove`/`onDelete` are nil, which removes the reorder and swipe-to-delete *gestures* rather than accepting them and refusing. A "LOCKED" badge sits under the trip name; tapping it asks before unlocking.
- **Map**: "Add to trip", the search fast-add "+", and "Remove from trip" all grey out, each showing a lock.
- **Backstop**: a single `guard activeTrip?.isLocked != true` in the three RootView mutation handlers, so a path we missed still cannot rewrite a finished trip.

## Two things worth knowing

- **The badge did not work at first.** It was placed inside the mode-toggle `Button`'s label, and SwiftUI does not deliver taps to a button nested in another button's label — it looked right and did nothing. It is now a sibling of that button. Caught before shipping only because the tap was checked rather than assumed.
- **`.confirmationDialog` rendered no visible Cancel** on iOS 26 — just title, message and "Unlock", leaving a background tap as the only way out. Switched to `.alert`, which shows both and matches the rename alert already in the file. Verified by screenshot.

## Not verified
The badge *tap* itself was not exercised: Simulator control was denied this session, so the alert was screenshotted by forcing its state rather than by tapping. The nesting bug above was found by reading the view tree, and the fix is structural. Worth one real tap on device.

## Also added
`-lockActiveTrip 1` launch arg (dev-only, alongside the existing screenshot aids) — locking is a two-tap journey through the "…" menu, tedious to drive for every capture.
