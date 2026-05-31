---
# AlaskaRouter-00iw
title: 'Bug: block-header separators lost the swipe-to-remove affordance'
status: completed
type: bug
priority: high
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T09:33:17Z
parent: AlaskaRouter-e0vm
---

After the collapse work the .onDelete swipe gesture seems to no longer work on block-header rows (regression flagged by user). Most likely cause: the .onTapGesture I added on the blockHeaderRow HStack (for tap-to-collapse) is consuming the horizontal swipe that List uses for .swipeActions/.onDelete.

Investigate:
- Confirm swipe-to-delete no longer works on block headers (vs stop rows where it still works).
- Diagnose: is .onTapGesture stealing the swipe? Try Button(role: collapseToggle) instead, or scope the tap to a smaller hit area.
- Fix and verify swipe-to-delete works on non-synthetic block headers.

## Summary
Caused by .onTapGesture on blockHeaderRow swallowing List's horizontal swipe. Wrapped the header content in a Button(action: onToggle) so SwiftUI routes tap-vs-swipe correctly. Swipe-to-delete on non-synthetic separators restored.
