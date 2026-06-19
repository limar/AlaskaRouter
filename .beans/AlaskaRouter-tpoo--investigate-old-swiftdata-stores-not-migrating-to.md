---
# AlaskaRouter-tpoo
title: 'Investigate: old SwiftData stores not migrating to add RouteSegment table'
status: todo
type: bug
priority: normal
created_at: 2026-06-19T03:25:49Z
updated_at: 2026-06-19T03:25:49Z
---

Observed on simulator iPhone 17 Pro (device 1785933B) container 1637E15F: default.store Z_PRIMARYKEY lists only BlockSeparator/Trip/Waypoint and ZTRIP lacks ZSNAPPEDROUTEROUTERVERSION — i.e. the store predates the y3g3 + un6b model changes and the current-schema app (Schema([Trip,Waypoint,BlockSeparator,RouteSegment])) did NOT add the RouteSegment table when it launched against it. Effect: on such a store the per-segment cache silently no-ops (SegmentCache lookups throw -> try? nil; stores fail on save -> try? swallowed), so segment caching/persistence is dead there even though rendering still works from in-memory snap results. Fresh stores (e.g. device 5E006E91) DO have ZROUTESEGMENT, so this is migration-from-old-store specific. Likely just an aged dev simulator, but if SwiftData lightweight migration genuinely isn't creating the new entity's table for upgrading users, that's a real data bug. Verify whether real upgrade installs are affected; if so add an explicit migration/versioned schema. Surfaced while debugging AlaskaRouter-d0wt.
