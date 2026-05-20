---
# AlaskaRouter-x605
title: Show leg direction (UI design + implementation)
status: todo
type: feature
priority: high
created_at: 2026-05-20T19:54:32Z
updated_at: 2026-05-20T19:55:13Z
parent: AlaskaRouter-xtua
---

Make the direction of travel along each leg of the route visually obvious. Today the route is bi-directional-looking — there's no cue that you're going Cantwell → Fairbanks vs the other way. Especially critical once multi-pass legs (3bot) are working and parallel ribbons need to read as 'this one outbound, this one return'. Needs design discussion before implementation.

## Why

Today the route line is direction-agnostic — looking at it, you can't tell whether you're going Cantwell → Fairbanks or the other way. That's fine for a single linear trip, but it falls apart for:
- Multi-pass legs (out-and-back) — the parallel ribbons (3bot) need to read as "this one outbound, this one return."
- Trips that cross themselves.
- Mid-trip review at a glance — "wait, where am I in this trip?" should be answerable without scanning the sheet.

## Status

**Design first.** Variants below. **DO NOT implement until user picks a direction.**

## Design variants to consider

### A. Small chevron arrows along the route (atlas convention)
Tiny `>` glyphs placed at regular spacing along the ribbon, pointing in travel direction. Like the arrows on a printed road atlas's "scenic byway" lines.
- Pros: classic, atlas-feel, works statically (no animation needed)
- Cons: easy to over-crowd; needs zoom-aware density

### B. Single chevron arrow at the start of each leg
One arrow near the leg's origin waypoint, pointing along the road toward the next stop.
- Pros: minimal, doesn't clutter
- Cons: easy to miss; doesn't help mid-leg

### C. White/black chevrons on the ribbon (high contrast)
Same as A but the chevrons are punched through the route color in white (light theme) or black, so they read against any block color.
- Pros: maximum legibility regardless of block color
- Cons: more visually loud; can feel "tech" rather than "atlas"

### D. Tinted chevrons (block color, darker)
Same as A but the chevrons are a darker shade of the ribbon's own color — feels native, not pasted on.
- Pros: stays in the warm palette, atlas-feel
- Cons: lower contrast; may disappear at small icon sizes

### E. "Wave" / "marching ants" running animation along the ribbon
Animated dash pattern that flows in the travel direction. Like Apple Maps' "this is your route" pulse but constant, not just on selection.
- Pros: directional cue is unmistakable; satisfying to watch
- Cons: animation may feel busy; potential battery/perf cost; doesn't survive a screenshot (so the static experience loses the cue)

### F. Asymmetric pencil-stroke shape
Render the ribbon as a tapered line — fatter at the leg start, thinner at the leg end (or vice versa). The taper IS the direction.
- Pros: atlas-feel, no extra glyphs needed, very subtle
- Cons: hard to perceive; doesn't really work on short legs

### G. Hybrid: static chevrons + animated wave on selection
Static D-style chevrons all the time; trigger an E-style wave animation only when a leg is selected (sheet tap, callout open). Best of both.
- Pros: no constant motion, rich feedback on interaction
- Cons: most implementation work

### H. Pin the previous waypoint's number "subscript-style" on the next leg
At each leg start, render "→ from #3" or similar. Direction is implicit in the "from" tag.
- Pros: very explicit
- Cons: text-heavy; clutters

## Compatibility with multi-pass (3bot)

Once 3bot's offset ribbons work, the same-color forth-and-back case needs direction to tell the two ribbons apart. Variants A/C/D/E/G all give the answer; B and F do not (B because both arrows would sit near the shared start, F because both ribbons would taper from the same end).

→ **Direction-distinguishing variants for 3bot: A, C, D, E, G.**

## Open considerations to discuss

- Should direction render at ALL zoom levels, or only mid/high zoom?
- Does the user want any animation at all, or "purely static / atlas" feel?
- For 3bot's parallel ribbons, should outbound and return be visually equal-weight, or should the "current direction" (most recent block) be emphasized?
- Cross-block consistency — if blocks have different colors and one block goes "north" and the next goes "south", the arrows should still point in travel direction within each block (not by compass).

## Checklist

- [ ] User picks a variant (or hybrid) from the list — DISCUSS FIRST
- [ ] Implement chosen variant
- [ ] Verify works correctly with single-leg routes
- [ ] Verify works correctly with multi-pass routes once 3bot lands
- [ ] Tune density / size / fade against zoom
- [ ] Side-by-side screenshot for each block color in the palette
