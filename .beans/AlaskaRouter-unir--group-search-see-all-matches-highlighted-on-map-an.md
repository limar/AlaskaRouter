---
# AlaskaRouter-unir
title: Group search — see all matches highlighted on map and pick
status: todo
type: feature
priority: normal
created_at: 2026-05-19T07:59:36Z
updated_at: 2026-05-21T15:12:22Z
parent: AlaskaRouter-xtua
---

Search 'campsite' + tap Enter -> all matching campsites in the current view are highlighted on the map. User can pan/zoom and tap any one to preview / add to trip.

Today the search dropdown shows the top N results as a list; user picks one. Group-search is the second mode: see them all in geographic context.

Open design questions:
- Trigger: Enter key, or a 'Show all' button in the results dropdown?
- Highlight style: different marker color/shape per category? Mass-render with no labels until zoom-in?
- Interaction with current preview pin and selected-stop styles?
- How does cancellation work (dismiss highlights when search bar cleared)?

- [ ] Design UI sketch
- [ ] Consult + get approval
- [ ] Implement query-all-results path in SearchService (today it returns top N)
- [ ] Render highlighted-results layer on the map
- [ ] Tap-highlighted-result -> preview callout, fast-add etc
