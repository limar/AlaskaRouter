---
# AlaskaRouter-x5ss
title: 'Bug: reorder finalize animation is slow with disappearing/reappearing rows'
status: scrapped
type: bug
priority: high
created_at: 2026-05-30T11:28:57Z
updated_at: 2026-05-30T11:47:11Z
parent: AlaskaRouter-e0vm
---

Regression user-spotted: dropping a moved stop or separator triggers a slow, lengthy finalize where the row vanishes at the old position, then reappears at the new one — instead of the standard slide-and-settle. Reads as identity-change-during-move rather than a true row move.

## Hypothesis (smallest reversible first)
blockHeaderRow was wrapped in Button(action: onToggle){...}.buttonStyle(.plain) in AlaskaRouter-00iw to fix swipe-to-delete being eaten by .onTapGesture. The Button's gesture system may now be competing with List's drag-to-reorder. TRY: replace the Button with a content-shape + .simultaneousGesture(TapGesture()) so tap-to-toggle coexists with drag and swipe without owning the row.

If that doesn't fix it, second suspect is applyReorderedItems doing many SwiftData mutations in a tight loop — possible mid-animation re-renders. Could batch via withTransaction or DispatchQueue.main.async.

## Reasons for Scrapping
The Button wrap → .simultaneousGesture swap did not fix the flicker on drop; root cause is elsewhere (likely main-thread synchronous work — most likely the expensive ribbon recompute that fires when the block-color/leg assignment changes). New direction to be explored in a follow-up bean focused on making the drop feel instant via deferred recompute.
