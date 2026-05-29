---
# AlaskaRouter-tluk
title: Human-readable categories + drop lat/long from waypoint info
status: in-progress
type: feature
priority: high
created_at: 2026-05-29T18:40:34Z
updated_at: 2026-05-29T18:44:17Z
---

Two coupled cleanups in the bottom sheet / callouts / search:

1. Categories were shown raw (OSM keys with _ → space), so the UI read "settlement major" / "settlement". Add a single CategoryLabel.display() mapping (settlement→Town, settlement_major→City, fuel→Gas, …) used by the bottom sheet stop row, StopCallout, PreviewCallout, and SearchResultsView. Unknown keys title-case as a fallback.
2. The bottom-sheet stop subline (kindHint) and PreviewCallout showed lat/long, which is useless to the user — removed. (StopCallout already shows distance, kept.)
3. Search: "Fairbanks town" couldn't find the "settlement" Fairbanks because "town" stayed a name token. Added town/city/village/hamlet → settlement(_major) to QueryParser.categoryPhrases so the descriptor is stripped from the name and applied as a (soft) category hint.

## Tasks
- [x] Add CategoryLabel helper
- [x] Apply CategoryLabel in kindHint / StopCallout / PreviewCallout / SearchResultsView; drop lat/long
- [x] Add town/city/village/hamlet synonyms to QueryParser
- [x] Tests — 29/29 pass incl. "Fairbanks town" battery case
- [x] Build + tests green\n- [ ] Verify visually on simulator (categories read friendly; no lat/long)
