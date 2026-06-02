---
# AlaskaRouter-ief3
title: Campground & POI data expansion — multi-source ingestion
status: completed
type: feature
priority: high
created_at: 2026-06-02T09:59:13Z
updated_at: 2026-06-02T13:04:43Z
parent: AlaskaRouter-xtua
---

Augment the unified offline places gazetteer (alaska-places.sqlite) with campground-focused and adjacent POI data from federal, state/local-GIS, OSM-enrichment, and private-directory sources identified in docs/'Data Sources and Integration Plan for an Alaska Campgrounds Database.md'. Build per-source fetch/scrape tools under tools/build-places/sources/ that each emit a common normalized candidate format, fold them into the existing dedup+FTS build, and document the whole effort so the data can be re-collected from scratch. Non-camping recreation POIs (cabins, trailheads, boat launches, ranger stations, picnic areas, visitor centers) are kept, not skipped.

## Source comparison — investigation vs. what we already use

Current pipeline (`tools/build-places/`) merges **3** sources into the unified gazetteer:
- **OSM** (Geofabrik → osmium tags-filter) — already ingested. Campgrounds come *only* from `tourism=camp_site,caravan_site` (→ `camping`) + huts. **All contact/booking tags are currently discarded** (only name-like tags survive). Biggest free win is here.
- **GNIS** + **Wikidata** — long-tail natural/cultural names; orthogonal to camping. The investigation does not mention these; we keep them.

New sources from the investigation, ranked for *our* constraints (keyless/OSS-leaning, reproducible, no paid subscriptions):

| Rank | Source | Access | Key? | Value | Notes |
|------|--------|--------|------|-------|-------|
| A | OSM contact/booking enrichment | already have PBF | no | high | zero new fetch, zero legal risk — just stop discarding tags |
| B | RIDB / Recreation.gov | REST JSON | free key (env) | high | authoritative federal (Chugach/Tongass NF, NPS, COE); non-camping facilities too |
| C | Alaska DNR State Park Boundary & Facility | ArcGIS REST | no | high | state campgrounds + cabins/trailheads/boat-launches |
| C | BLM AK Recreation FeatureServer | ArcGIS REST | no | med | overnight sites, campgrounds |
| C | Kenai Peninsula Borough Campgrounds | ArcGIS REST | no | med | dense for the planned route region |
| D | ACOA / AK Family Motorhomes / ACVB / Alaska.org | HTML scrape | no | med | private campgrounds absent from gov sources; robots.txt + geocoding gated |
| — | Active/ReserveAmerica | REST XML | key on request | low | heavy overlap w/ RIDB; defer unless gaps remain |
| — | AllStays / Campendium (Apify) | SaaS | **paid** | n/a | **DEFERRED** — paid subscriptions; user avoids subscriptions |

## Architecture decisions

1. **Keep the unified gazetteer model** — do *not* build a separate campgrounds-only DB. Fold campground richness into `place_meta` as additive, app-safe columns (`phone`, `website`, `booking_method`, `open_season`, `source_url`, all `TEXT DEFAULT ''`). App reads named columns, so this is backward-compatible; surfacing the fields in the UI is a *separate, non-blocking* follow-up feature.
2. **Common normalized candidate format.** Every new source fetcher writes `data/source-<name>.jsonl` in one shared record shape (defined in `sources/common.py`). `build_fts5.py` ingests `data/source-*.jsonl` generically and merges via the existing 2-pass coord+name dedup, with source-priority appended in order: federal > state/local > OSM > private (OSM/GNIS/Wikidata internal order preserved).
3. **Per-source tools live in `tools/build-places/sources/`**, each idempotent (`--force` to refetch), failing loudly on missing key / unreachable endpoint / robots-disallow (no silent fallbacks — house rule).
4. **Keep non-camping POIs.** ArcGIS facility layers and RIDB carry cabins, trailheads, boat launches, picnic areas, ranger stations, visitor centers — route them into existing categories (`hut`/cabin, `picnic`, `marina`, `ranger_station`, `visitor_center`) rather than dropping.
5. **Reproducibility.** README runbook documents every endpoint, the RIDB key acquisition, robots/ToS posture per scraped site, expected row counts, and a geocode cache so scrape re-runs don't hammer Nominatim.

## Stages (see child beans)
- Stage 1 — Schema + generic ingestion contract (foundation)
- Stage 2 — OSM contact/booking enrichment (highest ROI, no new fetch)
- Stage 3 — Federal: RIDB / Recreation.gov fetcher
- Stage 4 — State & local GIS: generic ArcGIS fetcher + layer registry
- Stage 5 — Private directories: polite scraper + geocoder (ToS-gated)
- Stage 6 — Cross-source dedup tuning, QA report, README runbook, ship

## Summary of Changes

Delivered across 6 stages (all child beans completed). The unified offline gazetteer grew from 3 sources to 8, with a repeatable per-source tooling layer under tools/build-places/sources/.

### Result
- DB: 33,470 -> 34,068 rows. Campgrounds 388 -> 493; public-use cabins 0 -> 293; huts -> 136. booking_method on 374 rows (online_portal 256), with phone/website/source_url and recreation.gov deep-links.
- New sources: RIDB/Recreation.gov (federal), BLM AK Recreation, Alaska DNR State Parks, Kenai Peninsula Borough (keyless ArcGIS), ACOA private campgrounds (robots-checked scrape + geocode). OSM contact tags now harvested too.
- schema v5: place_meta + phone/website/booking_method/open_season/source_url (additive, app-compatible).

### Repeatability
- sources/common.py SourceRecord contract; every fetcher idempotent (--force), fails loud, writes data/source-*.jsonl; build_fts5 globs them. run.sh is one-shot; qa_report.py validates. README documents endpoints, the RIDB key (.env), robots/ToS posture, and expected yields. Adding a source = write one fetcher (or one LayerSpec for ArcGIS).

### Notable
- Fixed a pre-existing bug: OSM ids were never captured (all osm_type='unknown').
- RIDB offset paging is unstable without sort=Name.
- Cross-source dedup uses source-priority + contact backfill + alt_names union; shared-URL/ID matching evaluated and skipped (no cross-provider shared ids).

### Deferred (follow-ups)
- AlaskaRouter-ytes: surface booking/phone/website in the app UI (data already ships).
- Broader private directories (Alaska Family Motorhomes, ACVB, Alaska.org) and paid AllStays/Campendium — out of scope (ACOA-only by decision; no paid subscriptions). The scrape_acoa.py pattern generalizes if wanted.
- In-app visual verification of campground search.

## Update — final numbers after fuzzy dedup (AlaskaRouter-lzrh)

After adding the normalized-name near-duplicate merge, the analysis the user prompted:
- Final DB: **33,977 rows** (was 34,068 before fuzzy merge; 33,470 at start). Camping 433, cabins 286, huts 112.
- Of the 460 external overnight rows, ~363 (79%) were genuinely NEW (not in OSM); the ~97 that overlapped OSM are now largely merged INTO the OSM row (enriching it with booking) rather than duplicated. Cross-source near-dup pairs within 250 m: 150 -> 32.
- Honest unique-added: net +507 rows over the original OSM/GNIS/Wikidata DB, dominated by RIDB public-use cabins and authoritative campground inventories OSM lacks. The headline non-OSM value is booking/reservation data (online_portal 251, recreation.gov deep-links) which OSM does not carry at all.
