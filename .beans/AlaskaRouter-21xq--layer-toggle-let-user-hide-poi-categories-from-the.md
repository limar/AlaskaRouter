---
# AlaskaRouter-21xq
title: Layer toggle — let user hide POI categories from the map
status: todo
type: feature
priority: low
created_at: 2026-05-25T14:34:44Z
updated_at: 2026-05-31T14:09:39Z
parent: AlaskaRouter-xtua
---

User feedback (2026-05-25):
> later we may want to add "layer" button where on sheet of "POI" user could remove checkboxes for POI types if wants to declutter.

## Scope

A sheet (or popover) listing each POI category with a toggle. Categories the user disables get filtered out of the visible map.

## Design sketch

- Trigger: small "layers" button on the right-rail map controls (above the +/− zoom buttons).
- Sheet: list of categories grouped by tier — Settlements, Natural, Services, Sights, Other.
- Each row: toggle + category name + count (e.g., "Peaks · 6,800 places").
- State persists via UserDefaults (TweaksStore).
- Implementation: pass the disabled-categories set into the MapLibre style layers as a filter expression (`!in category disabled-list`).

## Out of scope

- Per-zoom category visibility (the existing zoom-tier system handles that).
- Filtering search results — only affects map rendering.

## Checklist

- [ ] Layer-toggle sheet UI
- [ ] Persist disabled-categories set
- [ ] Wire filter expression into the places-tier-* style layers
- [ ] On-device verify
