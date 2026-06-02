---
# AlaskaRouter-13gz
title: Investigation & planning — campground/POI source review
status: completed
type: task
priority: high
created_at: 2026-06-02T10:00:09Z
updated_at: 2026-06-02T10:01:06Z
parent: AlaskaRouter-ief3
---

Review docs/'Data Sources and Integration Plan for an Alaska Campgrounds Database.md', compare proposed sources against the existing OSM+GNIS+Wikidata pipeline, and produce the staged work plan + architecture for tools/build-places/sources/. Output captured in the parent feature bean body.

## Summary of Changes

Reviewed the attached investigation against the existing OSM+GNIS+Wikidata pipeline. Key findings: (1) OSM is already ingested but all contact/booking tags are discarded — the cheapest high-value win; (2) GNIS/Wikidata are orthogonal long-tail name sources the investigation doesn't touch — keep them; (3) the app reads named DB columns, so new place_meta columns are backward-compatible. Decided to keep the unified gazetteer model (fold campground richness into additive columns rather than a separate campgrounds DB), adopt a common normalized candidate JSONL contract under tools/build-places/sources/, and rank sources for our keyless/OSS/no-subscription constraints (OSM-enrichment > RIDB > ArcGIS state/local > private scrape; AllStays/Campendium deferred as paid). Full plan + source comparison table captured in parent AlaskaRouter-ief3. Six implementation stages created as sibling beans with a blocked-by chain.
