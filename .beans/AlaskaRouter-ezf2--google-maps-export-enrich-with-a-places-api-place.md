---
# AlaskaRouter-ezf2
title: 'Google Maps export: enrich with a Places API place_id'
status: todo
type: feature
priority: deferred
created_at: 2026-07-30T22:17:56Z
updated_at: 2026-07-30T22:17:56Z
---

Post-2.0. Upgrades the shipped keyless Google export (AlaskaRouter-rvzg stage 1) from a coordinate-anchored labelled pin to Google's own rich POI card.

Split out of AlaskaRouter-rvzg on 2026-07-30 — stage 1 shipped and closed the field bug, so the remaining stages are enhancement, not fix. User scoped them out of v1.1, probably past 2.0.

## Where stage 1 left it
`comgooglemaps://?q=<lat>,<lon>(<name>)` — exact position, our name on the card, never wrong. What it does NOT get is Google's rich POI card (reviews, hours, photos), which hangs off a Places API `place_id` and cannot be had from URL syntax alone. That is the whole point of this bean.

## Stage 2 — Places lookup when a key exists
On share: `findplacefromtext` / Places Text Search biased to the waypoint coordinate -> take the top result **within a sanity radius** -> hand Google `?api=1&query=<name>&query_place_id=<id>`. Falls back to the stage-1 form on no key, no network, no match, or a match outside the radius.

**The radius check is the safety rail.** It is the thing that stops a confident, authoritative-looking card for a place hundreds of km away — exactly how the rejected G4 (name+borough) form failed, landing the Farthest North Spruce on North Slope Borough, ~245,000 km².

## Stage 3 — key onboarding worth the name
'Paste your API key here' is the baseline, not the goal.
- Guided setup screen: what the key is for, what it costs (Places has a free monthly tier), a direct link to the right Google Cloud console page, then paste.
- Store it in the **Keychain**, not UserDefaults/TweaksStore where every other setting lives. A credential is not a tweak.
- Visibly optional: with no key the export still works, so this is an upgrade prompt, not a wall.
- Rejected: shipping a key in the app (extractable, abusable, untenable for OSS) and running a proxy (hosting + account/privacy surface).

## Before starting
- [ ] Ask the user for a valid Google API key — they say it is easy to obtain
- [ ] **Check for an existing Swift SDK/framework for Google Places** before hand-rolling REST
- [ ] Stage 2: lookup + coordinate sanity radius + clean fallback + tests
- [ ] Stage 3: key onboarding + Keychain storage
- [ ] Field-verify on the real device
