---
# AlaskaRouter-ykuf
title: Waypoint icon redesign — readable number-on-icon
status: todo
type: feature
priority: high
created_at: 2026-05-22T12:52:08Z
updated_at: 2026-05-22T12:52:56Z
parent: AlaskaRouter-xtua
blocking:
    - AlaskaRouter-fooa
---

The fooa step 1 numbered waypoint icons reveal a contrast problem: the dark-brown digit sits on the icon's dark-red center pip and is hard to read. The icon visual was designed before numbers landed; it needs a rework where the digit is the readable focal element.

## What's wrong

After fooa step 1 landed digits inside the waypoint icons, the existing icon design fights the digit:

- The central pip is **warm tomato red (#c2410c-ish)**, dark and saturated.
- The digit is rendered in **dark brown** (~#52311a) with a cream halo.
- Dark-brown on dark-red is genuinely hard to read, especially at smaller icon sizes when the halo can't grow proportionally.

The icon was designed pre-numbers as "cream disc + brown ring + warm-tomato center" — when the center was just a decorative dot, this contrast was fine. Now the center is the digit's stage.

## Design directions (pick one or sketch a new one)

### A. Invert the center: cream pip + dark-red ring + dark-red digit
- Central pip becomes white/cream
- Digit drawn in dark red (or dark brown) on cream — high contrast
- Outer ring stays for outline definition

### B. Keep dark-red center, change digit color to cream/white
- Cream/white digit on dark-red center
- No halo (or tiny halo for legibility)
- Closer to "stamped seal" feel

### C. Move the digit OUT of the center into the cream ring
- Smaller digit drawn in the upper ring area
- Center stays as a pure decorative pip
- Works if the ring is wide enough

### D. New shape entirely: a "pin with circle head"
- Drop the disc-plus-pip combo
- Use a single colored circle with the digit centered
- Color = block accent (currently the digit's block context is already encoded in the route line)

## Constraints

- Must remain visually distinguishable between **default** (committedDefault, 44pt) and **selected** (committedSelected, 60pt) icons.
- Must compose with the iconScale zoom-interpolation from h82l (icon shrinks to ~0.3× at z=5 — digit must still be readable at mid zooms; deliberately fades at very low zoom in fooa step 2).
- Should match the warm-paper / atlas-station aesthetic of the rest of the v1 visual language.

## Open questions

- Do we want the icon's color to **vary with block color** (each block's stops use that block's color)? Today they're all the same warm-tomato regardless. With per-block icons, the digit would need a color that reads on any of the 6 block palette colors.
- Do **selected** icons need their own treatment (e.g., halo / outline) on top of the digit redesign?

## Related beans

- AlaskaRouter-fooa — numbered icons (delivered step 1; this redesign unblocks polish)
- AlaskaRouter-h82l — icon zoom-scaling (DONE; this redesign should preserve the zoom-scaling)
- AlaskaRouter-98jd — more distinguishing selected icon polish (related — same family of design concerns)
- AlaskaRouter-fuu4 — selected waypoint floating icon with shadow (related)

## Checklist

- [ ] Pick a design direction (A / B / C / D / sketch)
- [ ] Update WaypointIcons.swift to render the new icon
- [ ] If digit color changes, update SymbolStyleLayer text props in ExpeditionMapView
- [ ] Verify at z=5..15 — digit readable at mid zoom (z=9..12), gracefully fades or hides at low zoom
- [ ] Verify default + selected variants both work
- [ ] Verify against all block palette colors (if per-block coloring is in scope)
