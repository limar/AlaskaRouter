---
# AlaskaRouter-q1qn
title: 'Tests: defer map UI automation until stable'
status: draft
type: task
priority: deferred
created_at: 2026-05-27T08:08:16Z
updated_at: 2026-05-27T08:30:40Z
parent: AlaskaRouter-kupb
---

Capture deferred visual/UI automation work so it is intentional, not forgotten.

- [ ] Revisit after v1 UI/map interactions stabilize
- [ ] Decide whether to use snapshot tests, UI tests, or manual screenshot scripts
- [ ] Identify MapLibre/map visual cases worth automating
- [ ] Keep current approach as manual device/simulator verification plus targeted spikes

## Deferral Note

This remains intentionally deferred. The current test pass added stable unit/integration coverage for data, search, and TripStore behavior. MapLibre rendering and SwiftUI snapshot/UI automation are still poor fits because the map visual language, layer behavior, and UI polish are actively changing. Revisit after v1 interaction and visual design stabilize; until then, continue using manual device/simulator verification plus targeted visual spikes.
