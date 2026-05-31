---
# AlaskaRouter-d1d6
title: 'Bug: search DB has duplicate/triplicated entries (e.g. ''North Pole'', ''Nenana'')'
status: completed
type: bug
priority: high
created_at: 2026-05-24T17:07:57Z
updated_at: 2026-05-24T18:07:21Z
parent: AlaskaRouter-22h7
---

User-visible: searching "Nenana" returns multiple identical-looking rows; same for "North Pole", "Gainor Beach", "Nenana Mountain", etc.

## Hypothesis

The current dedup key is `(name.casefold(), round(lat, 3), round(lon, 3))` with `ROUND_COORD_DIGITS=3` ≈ 150 m. Same-name entries from different sources (OSM / GNIS / Wikidata) likely don't collide when:
- coords differ by >150 m (different sources can locate the same feature at different "centroid" points), or
- name capitalization / punctuation / unicode differs subtly between sources.

This is a build-pipeline dedup bug, not a data-model design problem — the schema supports a `source` column precisely so we can keep provenance per row while merging into one logical entity.

## Investigate

- [ ] Confirm via SQL: for each user-reported duplicate, what's the per-source row breakdown? Coord delta? Name string delta?
- [ ] Decide whether to (a) loosen the coord round to ~500 m, (b) add a second-pass name-based dedup independent of coord, or (c) both
- [ ] Apply, rebuild, count delta. Report final entry total.

## Fix

- [ ] Update `build_fts5.py` dedup pass
- [ ] Rebuild + verify the listed examples no longer triplicate
- [ ] Copy new pois.sqlite to AlaskaRouter/Resources/alaska-places.sqlite


## Summary of Changes

Root cause was as hypothesized: the single-pass dedup keyed on `(name.casefold(), round(lat, 3), round(lon, 3))` (≈150 m N-S, ≈50 m E-W at 64°N) couldn't catch cross-source duplicates where sources legitimately disagreed by 100–500 m on the feature centroid. Same name + slightly different rounded coord → two rows.

### Fix

Two-pass dedup in `build_fts5.py`:

1. **Pass 2a** — cheap dict-key dedup on `(name.casefold(), lat~150m, lon~150m)`. Unchanged from before. Catches the easy case.
2. **Pass 2b (NEW)** — name-cluster dedup. Group survivors by casefold name; within each group, greedy spatial clustering with a 5 km haversine threshold. Keep highest-importance row per cluster; ties resolve to first-encountered (preserves OSM > GNIS > Wikidata source priority because the candidate list is built in that order).

The 5 km threshold is generous enough to absorb cross-source centroid drift (OSM's 64.751/-147.349 + Wikidata's 64.751/-147.352 for "North Pole" — 250 m apart — now merge) but tight enough that distinct "Smith Creek"-type features in different towns stay distinct.

### Result

- **Before:** 42,913 entries
- **After:** 33,470 entries
- **Removed by pass 2b alone:** 9,443 duplicate rows (~22 %)
- **Source survivors:** OSM 15,271 / GNIS 12,630 / Wikidata 5,569
- DB size: 10 MB → 8.3 MB (smaller)

Verified user-reported examples are now single-row: North Pole, North Pole Hill, Nenana Mountain, Nenana Municipal Airport. Cases remaining at 2 rows (Gainor Beach, Nenana glacier vs. parking, Nenana Glacier) are real data-quality issues in Wikidata or genuine distinct features sharing a name >5 km apart — correctly NOT merged. Fixing those is a separate concern (filter bad Wikidata coords).
