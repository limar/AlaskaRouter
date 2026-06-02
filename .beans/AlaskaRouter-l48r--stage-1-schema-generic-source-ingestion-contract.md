---
# AlaskaRouter-l48r
title: Stage 1 — Schema + generic source-ingestion contract
status: completed
type: task
priority: high
created_at: 2026-06-02T10:00:09Z
updated_at: 2026-06-02T10:45:35Z
parent: AlaskaRouter-ief3
---

Foundation for all new sources. No new data yet.

- [x] Added place_meta columns phone, website, booking_method, open_season, source_url (TEXT DEFAULT ''); SCHEMA_VERSION 4 -> 5.
- [x] Verified backward-compat: app SELECTs named columns and has NO schema_version gate; appended columns are invisible to it. No app change.
- [x] sources/common.py: SourceRecord dataclass (+validate), write_jsonl/read_jsonl, Candidate NamedTuple (positionally compatible with the old 9-tuple + 5 v5 fields), source_of(), stable_id(). No third-party deps.
- [x] build_fts5.py external_candidates(DATA) globs data/source-*.jsonl, assigns importance, carries v5 fields through dedup. Appended after OSM/GNIS/Wikidata (external loses ties for now; true source-priority + empty-field backfill deferred to Stage 6). Dedup/admin-inheritance refactored to NamedTuple (_replace, named access).
- [x] IMPORTANCE added: cabin 0.5, trailhead 0.45, boat_launch 0.4, dump_station 0.3 (camping/picnic already present). CategoryLabel additions deferred to Stage 4 when those categories first appear.
- [x] Acceptance PASS: rebuild = 33,470 rows; per-source (osm 15271 / gnis 12630 / wikidata 5569) and ALL per-category counts identical to the old-code baseline; 5 new columns present and 0 non-empty; metadata gained external_count + source_counts.

## Summary of Changes

Foundation for multi-source ingestion, behavior-preserving for the existing build.

- NEW tools/build-places/sources/{__init__.py, common.py} — the source contract: SourceRecord (fetcher-facing, validated) + write_jsonl/read_jsonl; Candidate (internal pipeline NamedTuple, positionally compatible with the historical 9-tuple so the dedup engine is untouched, plus 5 v5 fields); source_of()/stable_id() helpers.
- NEW tools/build-places/.env.example (committed) + .env (gitignored) for RIDB_API_KEY and future keys; .gitignore now blocks .env, **/ridbapi.txt, __pycache__.
- build_fts5.py: schema v5 adds place_meta.{phone,website,booking_method,open_season,source_url} (TEXT DEFAULT ''); external_candidates() ingests data/source-*.jsonl generically; dedup/admin-inheritance/insert/geojson paths moved to named Candidate access. New metadata keys external_count, source_counts, external_pre_dedup.
- Verification: with no source-*.jsonl present, a full rebuild from the same OSM+GNIS+Wikidata inputs reproduces the prior DB exactly (33,470 rows; per-source and per-category counts identical) with the 5 new columns present and empty. App needs no change. DB NOT yet swapped into Resources — deferred to Stage 6.

Unblocks Stages 2-5.
