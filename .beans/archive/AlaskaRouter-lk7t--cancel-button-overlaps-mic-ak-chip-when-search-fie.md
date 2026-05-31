---
# AlaskaRouter-lk7t
title: Cancel button overlaps mic + AK chip when search field is focused
status: completed
type: bug
priority: normal
created_at: 2026-05-19T09:41:32Z
updated_at: 2026-05-19T09:43:39Z
parent: AlaskaRouter-xtua
---

When the user focuses the search field, FloatingSearchBar replaces the mic icon + AK profile chip on the right with a tomato 'Cancel' text button. Two issues:

1. The mic icon and AK chip are nice-looking elements the user wants visible at all times.
2. The user can already cancel by tapping outside (the dim layer in RootView calls dismissSearch).

Fix: remove the Cancel button entirely; always show mic + AK chip. Also align dismissSearch with the old Cancel semantics by clearing the query (currently it only blurs the field).

- [x] Remove the Cancel branch in FloatingSearchBar
- [x] Update RootView.dismissSearch to also clear the query
- [x] Verify focused state shows mic + chip; tap-outside still cancels everything

## Summary of Changes

- FloatingSearchBar.swift: dropped the if/else that swapped mic+AK chip for a tomato 'Cancel' text button when fieldFocused || !query.isEmpty. Mic and chip now show in all expanded states. Removed the now-unused cancelSearch() helper.
- RootView.swift: dismissSearch() now always clears the query, blurs the field, and collapses the bar — symmetric to what the old Cancel button did. Tap-outside (the dim layer) is the sole dismiss path.

Verified focused + query='Coldfoot Air' state in simulator: mic icon and AK chip both render under the magnifying glass on the right; results dropdown still anchors under the bar.
