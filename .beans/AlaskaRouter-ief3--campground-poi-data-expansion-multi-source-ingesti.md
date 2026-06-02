---
# AlaskaRouter-ief3
title: Campground & POI data expansion — multi-source ingestion
status: in-progress
type: feature
priority: high
created_at: 2026-06-02T09:59:13Z
updated_at: 2026-06-02T09:59:45Z
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
