---
# AlaskaRouter-1ag5
title: Sheet translucency vs muted text — opacity/contrast pass
status: todo
type: feature
priority: normal
created_at: 2026-05-30T09:43:13Z
updated_at: 2026-05-30T09:43:13Z
parent: AlaskaRouter-e0vm
---

**The gotcha**: our bottom sheet is .thinMaterial (Apple-glass translucent over the map). The mock used a solid opaque background, so muted/italic text reads strong there. On us, every muted color dissolves into whatever the map is showing through at that moment — bright sand under the sheet swallows .textMuted especially badly.

This is **cross-cutting** (not a per-text tweak): every muted color in the sheet (italic header names, sublines, secondary stats, the rail-distance label) is affected. Don't fight it by darkening each color individually — addresses the wrong layer.

## Options to TRY (in order of preference)
1. **Heavier material** — .regularMaterial or .thickMaterial instead of .thinMaterial. Cheapest first cut.
2. **Hybrid: solid inset card + glassy outer chrome** — let the *list card* (cardFill) be more opaque while the outer sheet stays translucent. The list content sits on a real card, the chrome around it stays Apple-ish. We sort-of already have this — push it further.
3. **Custom blur weight** — Material.thin with an underlying ColorMaterial overlay.
4. **Bravely solid** — only if the hybrid still doesn't read. Trades the translucent identity for predictable contrast.

## Deferred until
After the rest of the round-2 rework lands (sheet visual baseline shifts a lot between now and then). Re-evaluate then.
