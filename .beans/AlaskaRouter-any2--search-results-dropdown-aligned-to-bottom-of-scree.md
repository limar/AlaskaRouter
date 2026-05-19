---
# AlaskaRouter-any2
title: Search results dropdown aligned to bottom of screen instead of below search bar
status: todo
type: bug
priority: high
created_at: 2026-05-19T07:34:55Z
updated_at: 2026-05-19T07:34:55Z
parent: AlaskaRouter-xtua
---

Type into the search bar -> the single result row appears pinned at the BOTTOM of the screen, just above the safe-area inset, instead of attached directly under the search bar at the top. See user screenshot: query 'Coldfoot Air' yields one result 'Coldfoot Airport' shown ~700px below the search field.

Basic functionality regression — likely a VStack-layout issue in RootView where the results panel is placed after a Spacer instead of immediately under the search bar.

- [ ] Reproduce in simulator
- [ ] Inspect RootView layout (likely results-panel placement vs Spacer)
- [ ] Fix layout: results dropdown should anchor to bottom-of-search-bar
- [ ] Verify with screenshot at 1, 3, 7 result rows
