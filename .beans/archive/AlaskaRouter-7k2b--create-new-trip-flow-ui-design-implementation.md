---
# AlaskaRouter-7k2b
title: Create-new-Trip flow (UI + design + implementation)
status: completed
type: feature
priority: high
created_at: 2026-05-19T07:35:02Z
updated_at: 2026-05-19T11:08:09Z
parent: AlaskaRouter-xtua
---

Main v1 functionality, currently missing. Single sample trip is seeded on first launch (SampleTrip.swift), but the user has no way to create a brand-new trip. Need: UI to start a fresh empty trip (name, optional color), trip switcher / list, deletion of trips.

- [ ] Design UI (sketch + consult user before building)
- [ ] Get design approved
- [ ] Implement Trip-create entry point (where in chrome? new-trip button on bottom-sheet header, or in collapsed pill?)
- [ ] Implement trip list / switcher
- [ ] Implement trip delete
- [ ] Wire SwiftData create/delete operations
- [ ] Verify search -> add-to-trip still works when active trip changes



## Summary of Changes

Five steps, four commits:

1. **TripStore + persistence** (28da40a) — new file owning activeTripID UserDefaults + bootstrap on first launch + create/delete/rename helpers. RootView.activeTrip resolves via TripStore. SampleTrip moved behind -seedDemoTrip launch arg.
2. **Welcome overlay** (30bdb1e) — one-time first-launch card in Marker Felt + a Path-drawn wobbly arrow pointing at the bottom sheet. Tap-anywhere dismiss, gated by UserDefaults['hasSeenWelcome'].
3. **Trips overlay in bottom sheet** — tappable header (name + chevron) toggles between .stops and .trips modes. Trips list shows all trips with active-trip checkmark, tap-to-switch, trash icon → iOS-native confirm alert → delete. 'New Trip' row at the bottom instantly creates 'Trip from <today>' with default name and switches to it.
4. **Header pencil + rename** — small material-backed pencil icon next to the active trip name; tap opens an iOS alert with TextField. Save commits via TripStore.rename.
5. **Empty state for zero-stop trips** — when active trip has no waypoints, the sheet shows a 'No stops yet' hint with mappin icon and prompt to use the search bar above.

Edge cases handled:
- Delete the only trip → TripStore auto-bootstraps a new empty one so the app is never trip-less.
- Search bar autocorrection issue (place names aren't English words) flagged as a separate bean AlaskaRouter-ox6r.
- Per-trip color picker removed from scope — color belongs per-block (see AlaskaRouter-7nxj).

Dev launch args added: -tripsMode YES (open sheet directly in trips list), -hasSeenWelcome YES (skip the welcome card), -seedDemoTrip YES (re-seed the Parks Highway demo trip).
