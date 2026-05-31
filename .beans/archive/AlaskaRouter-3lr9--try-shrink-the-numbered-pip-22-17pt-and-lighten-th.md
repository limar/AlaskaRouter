---
# AlaskaRouter-3lr9
title: 'Try: shrink the numbered pip (22 → ~17pt) and lighten the outer ring'
status: completed
type: task
priority: high
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T10:48:03Z
parent: AlaskaRouter-e0vm
---

Mock pip is 16pt; we hold the timeline rail so a touch more presence (~17–18pt) is probably right. Drop the heavy 1.6pt block-color stroke to ~1.2pt; the pipOuterRing (dark-mode cream halo) can probably go to 0.5pt or be dropped entirely if the rail is providing enough block-color identity. Number stays (per user — mirrors map markers).

Try in steps so we can stop early: (1) just the diameter, (2) then the stroke weights.

## Summary
Shrank the numbered pip from 22pt → 17pt (stroke 1.6 → 1.4, outer ring proportionally scaled 24.4 → 18.8 with 0.6pt stroke, digit font 10 → 9pt). Block-header chip stays at 22pt — the contrast now reinforces the section/stop hierarchy (chip > pip). 6-dot drag glyph also tightened: spacing 4 → 2pt, dragColWidth 14 → 12pt, dot diameter 2.5 → 2pt — reads as one compact glyph instead of a sparse halftone, mock-aligned.
