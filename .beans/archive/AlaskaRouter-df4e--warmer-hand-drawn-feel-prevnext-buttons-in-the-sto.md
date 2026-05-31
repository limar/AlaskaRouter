---
# AlaskaRouter-df4e
title: Warmer, hand-drawn-feel Prev/Next buttons in the stop callout
status: scrapped
type: feature
priority: normal
created_at: 2026-05-20T09:05:56Z
updated_at: 2026-05-31T14:07:00Z
parent: AlaskaRouter-xtua
---

The Prev/Next chevrons in the StopCallout (and possibly elsewhere) currently use bare SF Symbol chevron.left / chevron.right with the default semibold-system font weight. Functional but visually 'lame' — they read as iOS chrome dropped onto an otherwise warm, atlas-style canvas. Everything else on the map has character now: drunk-geologist pencil route line, OpenTopoMap terrain, cream paper materials, hand-drawn welcome overlay. The nav buttons should match.

Directions to explore:

- **Hand-drawn arrows** rendered as SwiftUI Paths with subtle wobble — same vibe as the welcome overlay's WobblyArrow. Probably 1.8–2.2pt stroke, a touch hand-tremor on the shaft.
- **Marker-Felt or similar handwritten font** for '< >' or '← →' glyphs. Already bundled (welcome overlay uses Marker Felt).
- **Cream rounded chip** behind the arrow — pencil-on-paper feel, slight rotation/skew for a sticker quality. Matches the welcome overlay's note card aesthetic.
- **Pencil-stroke arrows** — like the drunk-geologist route, with slight transparency and tapered ends.
- **Tactile shadow** — small drop-shadow + bottom-edge highlight so the button feels lifted / pressable.

Apply to:
- StopCallout Prev / Next (the immediate motivation)
- Probably also the Welcome overlay's tap-to-dismiss hint, and any future nav-style buttons
- Consider the bottom-sheet trash + the FloatingSearchBar mic/AK chip — separate beans if they need similar treatment, this one stays scoped to Prev/Next

Acceptance: side-by-side comparison shows the new buttons feel like part of the atlas (warm, slightly imperfect, inviting) rather than borrowed iOS controls. User's litmus: 'as inviting as home slippers.'

- [ ] Sketch 2–3 button variants (Path-drawn arrow, Marker-Felt glyph, cream chip + arrow)
- [ ] Screenshot each in the callout, side-by-side
- [ ] Pick with user; bake in
- [ ] Optional follow-up: extend to other plain chrome buttons
