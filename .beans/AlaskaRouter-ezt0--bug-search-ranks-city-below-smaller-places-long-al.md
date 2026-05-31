---
# AlaskaRouter-ezt0
title: 'Bug: search ranks city below smaller places — long alt_names skews BM25 (Fairbanks/Anchorage)'
status: in-progress
type: bug
priority: critical
created_at: 2026-05-31T14:42:25Z
updated_at: 2026-05-31T15:11:43Z
parent: AlaskaRouter-xtua
---

Typing the exact name of a major city does not return the city as the first result.

## Reproduce

- Search "Fairbanks" → first hit is "Fairbanks Park" (a small Anchorage neighborhood). The city Fairbanks isn't even in the top 10.
- Search "Anchorage" → first hit is "Baldwin Seaplane Anchorage". The city Anchorage isn't in the top 10.
- Workaround the user found: "Fairbanks settlement" (extra descriptor token) surfaces the city via the category-hint boost.

## Root cause (verified against the bundled DB)

`SearchService.swift` strict-stage scoring:

```sql
ORDER BY bm25(places_word) - m.importance * 5.0 - catBoost ASC
```

The FTS5 virtual table `places_word(name, alt_names, category, region)` is indexed across all 4 columns with default unit weights, so BM25 treats the *combined* string as one document. The major-city rows carry huge multilingual `alt_names`:

- `Fairbanks` → 226 chars of alt_names (Russian, Greek, Arabic, Japanese, Korean, Chinese, Hebrew, …)
- `Anchorage` → 369 chars of alt_names (40+ translations + "Municipality of Anchorage")

That inflates document length, which crashes the BM25 score for the city below short-doc rows like "Fairbanks Park" or "Anchorage Trails". The `- importance * 5.0` term (city has importance 1.0) is not large enough to overcome the BM25 gap.

Empirical scores for `fairbanks*` (lower = better):

```
14433  Fairbanks Park                          score -10.72
11711  Fairbanks International Airport         score -10.59
 9812  Mount Lulu Fairbanks                    score -10.09
…
  323  Fairbanks (the city)                    NOT in top 10
```

## General fix (no hardcoded names)

Three principled levers — likely a combination of (a) + (b):

(a) **Exact-name / name-prefix boost** in the scoring SQL. When `LOWER(m.name) == joinedQuery` add a large negative term (e.g. -50); when `LOWER(m.name) LIKE joinedQuery || ' %'` add a smaller boost (e.g. -15). "Anchorage" then dominates "Anchorage Museum" cleanly, and "Anch" still favors "Anchorage" over "Anchorage Bowl".

(b) **FTS5 column weights** — `bm25(places_word, w_name, w_alt, w_cat, w_region)`. Weight name 5–10× more than alt_names so multilingual transliterations stop dragging the city down.

(c) Bigger `importance` multiplier (5.0 → ~15.0). Cheapest patch but blunt — would also shift the strict-stage ranking for queries we're already happy with. Probably keep at 5.0 if (a)+(b) land.

## Checklist

- [x] Add joined-query string (lowercased name-tokens joined by space) into the scoring SQL of `stage1Query` in [SearchService.swift](AlaskaRouter/Search/SearchService.swift)
- [x] Add a CASE boost: exact name match (-50), `name LIKE query%` with word boundary (-15)
- [x] Switch `bm25(places_word)` → `bm25(places_word, 10.0, 1.0, 1.0, 1.0)` so name dominates alt_names
- [x] Add unit tests (Tests/SearchTests.swift): testExactNameMatchOutranksLongerSamePrefixPlaces, ...PlacesAnchorage, testMultiWordExactMatchStillWorks — all passing.
- [ ] On-device verify both queries

## Summary of Changes

- [SearchService.swift](AlaskaRouter/Search/SearchService.swift) `stage1Query`: new exact-name (-50) + name-prefix-with-word-boundary (-15) CASE boost, bound from the lowercased joined query tokens. `bm25(places_word)` → `bm25(places_word, 10.0, 1.0, 1.0, 1.0)` to weight the `name` column 10× over `alt_names`/`category`/`region`.
- `runRowidSQL` extended with a `nameBoostQuery` parameter; binds the query string for the equality branch and `query + " %"` for the prefix-LIKE branch.
- Tests in [Tests/SearchTests.swift](Tests/SearchTests.swift) lock the new ranking for `Fairbanks`, `Anchorage`, and the regression case `Fairbanks Park` (multi-word exact match must still win).
- Empirically against the bundled DB: `fairbanks*` now scores Fairbanks the city at −64 vs Fairbanks International Airport at −32; `anchorage*` scores Anchorage at −61 vs Anchorage Trails at −30.

## Follow-up (not addressed here)

The edit-distance fallback (`stage2Query`) uses the first 3 chars of the query as the prefix filter. A typo like "Firebanks" produces `fir*` which doesn't match anything starting with "fair", so the city is excluded from the candidate set entirely. Separate fix needed (smaller prefix, or substring-based candidate selection). Worth a follow-up bean if the user typoes a lot.
