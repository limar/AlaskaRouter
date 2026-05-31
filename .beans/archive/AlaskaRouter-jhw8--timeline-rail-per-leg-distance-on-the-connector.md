---
# AlaskaRouter-jhw8
title: Timeline rail + per-leg distance on the connector
status: completed
type: task
priority: high
created_at: 2026-05-29T19:35:36Z
updated_at: 2026-05-30T06:50:18Z
parent: AlaskaRouter-e0vm
---

Add the mockup's block-colored vertical connector rail through the stop pips (design/mocks/sheet.jsx StopRow), and place each leg's distance ON the rail in the gap between two stops — so the distance is spatially unambiguous (no from/to wording needed). Replaces the inline 'Category · 23 km' subline (the subline goes back to just the category).

## Plan
- [x] Add a leading rail column to the stop row: top segment + pip + bottom segment, block-colored. First stop: no top segment. Last stop: no bottom segment.
- [x] Place the incoming-leg distance on the top segment (between the previous pip and this pip), horizontal text breaking the line.
- [x] Revert the stop subline to category-only (distance now lives on the rail).
- [ ] Handle block-boundary leg (connector breaks at header in the mock) — decide where its distance shows.
- [x] Build + self-screenshot (live Alaska trip). Fixed a position-vs-.order bug (first stop showed a phantom leg). Index legs by position now.\n- [x] User visual verify — approved ("good functional improvement"). Tuning + block-boundary refinement left as follow-ups under the epic.

## Note — block-boundary rail
At a block boundary the connector leg's distance (e.g. '67 km') shows above the block's first stop, under the header, with a short floating rail segment (the header row has no rail). Acceptable for v1; refine later (the deferred checkbox in the plan).

## Summary of Changes
Added the mockup's block-colored timeline rail through the stop pips (top + bottom half-segments per row, first/last hidden) and placed each leg's distance ON the connector in the gap between two stops, with a sheet-bg break behind the text. Stop sublines reverted to category-only (CategoryLabel) since the distance moved to the rail. Indexed legs by POSITION in orderedWaypoints (not .order) so the first stop never gets a phantom incoming leg even when orders aren't 0-based. Self-verified on the live Alaska trip; user approved.
