---
# AlaskaRouter-cwmd
title: Bottom sheet stays in Trips list after adding a stop from search
status: completed
type: bug
priority: high
created_at: 2026-05-19T11:29:34Z
updated_at: 2026-05-19T12:01:42Z
parent: AlaskaRouter-xtua
---

Repro: open the trip switcher (chevron next to trip name) → bottom sheet shows .trips mode listing all trips. Tap the search bar → sheet hides. Type a query, tap + to add a result. After the add, the sheet reappears — but it's STILL in trips-list mode rather than showing the stops of the active trip where the new stop was just inserted.

Expected: after adding a stop, the sheet should show the stops list of the active trip with the newly-added stop visible/selected.

Hypothesis: when the search-active condition flips false→true→false, SwiftUI either preserves the sheet's @State (against my understanding) or the @State init reads LaunchArgs.startInTripsMode on re-init. Either way the mode is not reset back to .stops on a successful add.

Fix: react to waypoint-count change inside TripBottomSheet via .onChange(of: trip.waypoints.count). When a stop is added (count goes up while in .trips mode), force mode back to .stops so the user immediately sees the result of their action.

- [x] Add .onChange(of: trip.waypoints.count) in TripBottomSheet — reset mode to .stops on add (turned out NOT to fire — SwiftData @Relationship array count changes don't reliably propagate through SwiftUI observation)
- [x] Fix actually: lifted SheetMode from TripBottomSheet's @State to a @State+@Binding pair owned by RootView, set sheetMode=.stops in both handleFastAdd and handleAddPreviewed
- [x] Verify by adding a stop while in trips mode

## Summary of Changes

Lifted SheetMode out of TripBottomSheet into RootView. The sheet now takes @Binding var mode instead of private @State var mode, and RootView owns the source-of-truth @State sheetMode. Both add handlers (handleFastAdd, handleAddPreviewed) now set sheetMode = .stops alongside the other post-add state changes. Verified with -tripsMode YES -prefillQuery Healy -autoAction add:0: sheet correctly lands in .stops showing the new stop, not in .trips.
