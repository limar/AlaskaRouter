---
# AlaskaRouter-7k2b
title: Create-new-Trip flow (UI + design + implementation)
status: in-progress
type: feature
priority: high
created_at: 2026-05-19T07:35:02Z
updated_at: 2026-05-19T10:08:42Z
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
