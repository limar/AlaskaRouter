---
# AlaskaRouter-yxve
title: Dark theme contrast pass on the bottom sheet, stop callout, and trip list
status: in-progress
type: task
priority: high
created_at: 2026-05-23T17:54:03Z
updated_at: 2026-05-23T18:28:28Z
---

## Problem (verbatim from user, 2026-05-23)

> Dark theme (which strikes automatically on my phone in the evening) is not well designed, some UI looses contrast and requires update. The bottom sheet is the main point of pain. Text is not seen very well while the reddish buttons are VERY hardly divisible. Same for the trip list, same for the waystops. Waystop icons are on the bright side, pretty visible BUT their outer border blends into the sheet background. Similar problem for the waystop callout, the gray&small text lost its contrast and the reddish delete button is not divisible. But the waypoint/title in white is seen perfectly.

## Root cause

`AlaskaRouter/UI/SheetPalette.swift` is the warm-paper palette and **every token is a fixed RGB literal** designed for light mode:

| Token | Light-mode value | Dark-mode effect |
|---|---|---|
| `surfaceTint` | cream `(252,250,244)` @ 0.30 | muddy beige over dark material |
| `textStrong` | near-black `(26,26,26)` | nearly invisible on dark sheet |
| `textMuted` | dark olive @ 0.55 | barely visible |
| `textEyebrow` | dark olive @ 0.60 | barely visible |
| `cardFill` | white @ 0.55 | too bright; throws contrast off |
| `cardBorder`, `rowDivider`, `blockHeaderBg` | black wash | invisible on dark |
| `destructive` | warm red `(0.78,0.32,0.20)` | dark-on-dark — invisible |

Same warm red is hardcoded in `StopCallout.itemColor()`.

The numbered pip on stop rows hardcodes `Color.white` fill + `accent` (block color) stroke. In dark mode the white pip is a bright disc on dark sheet (fine), but the block-color stroke (amber, terracotta, etc.) loses contrast against the warm-sepia-toned dark sheet because the hues are too close in luminance.

## Design strategy options

### A. Per-call-site dark variants
Each problematic `Color(red:…)` becomes a `Color(UIColor { trait in … })` inline. Surgical, narrow blast radius — but spreads the dark-mode logic across many files.

### B. Adaptive palette tokens (recommended)
Refactor `SheetPalette` so each static let returns an *adaptive* `Color`:
```swift
static let textStrong = Color(UIColor { trait in
    trait.userInterfaceStyle == .dark
        ? UIColor(red: 240/255, green: 232/255, blue: 210/255, alpha: 1.0) // warm cream
        : UIColor(red:  26/255, green:  26/255, blue:  26/255, alpha: 1.0) // near-black
})
```
View code stays unchanged — only the palette file changes. Centralizes dark-mode design in one place. Adds the StopCallout's hardcoded red into the palette too.

### C. Apple system semantic colors
Use `.primary`, `.secondary`, `Color(.systemRed)`, etc. — they adapt natively. Easiest but breaks the warm-paper aesthetic, which is a v1 design pillar.

## Recommended approach: B + small tweaks

1. **Palette refactor**: every fixed-RGB token in `SheetPalette` gets a dark variant. Design intent for dark mode = "warm campfire-lit paper" (same warm hue, inverted luminance) rather than the system grey-on-grey default. This preserves the atlas-paper feel after sunset.

2. **Dark palette draft** (open to discussion):
   - `surfaceTint`: warm dark wash, `(60,50,20)` @ 0.20 over dark material → reads as "lamp-lit page edge"
   - `textStrong`: warm cream `(240,232,210)` — same as basemap bg
   - `textMuted`: warm beige `(212,200,168)` @ 0.78
   - `textEyebrow`: warm beige @ 0.65
   - `cardFill`: warm dark wash `(50,40,18)` @ 0.40 → a "deeper page" inset
   - `cardBorder` / `rowDivider`: cream `(240,232,210)` @ 0.10
   - `blockHeaderBg`: cream @ 0.06
   - `destructive`: brighter warm red `(225,90,58)` — lifted luminance so it pops on dark
   - `statOk`: brighter green `(60,170,90)`
   - `statWarn`: brighter amber `(240,120,40)`

3. **Pip stroke contrast**: in dark mode the numbered pip's outer stroke should bump up from 1.6pt to ~2pt OR get a thin contrasting outer ring (cream @ 0.30, 1pt outside the colored stroke). Keeps the block-color identity readable.

4. **StopCallout fold-in**: replace its inline `Color(red: 0.78,…)` with `SheetPalette.destructive` so it adapts automatically. Same for any other hardcoded warm-red.

## Out of scope

- Map waypoint Dot icons — they're raster-baked at icon-generation time (`WaypointIcons.swift`). They use the same block colors, and on the live map (with the topo background) they look fine. If they need a dark-mode variant later, that's a separate bean (would require regenerating per-trait at runtime).
- Bottom-sheet *material* (`.thinMaterial`) already adapts via the system; we don't touch that.

## Checklist

- [x] Refactor `SheetPalette` tokens to adaptive `Color(UIColor { trait in … })` — every token gets a dark variant (warm campfire-paper aesthetic).
- [x] Route StopCallout, AddedToTripToast, PreviewCallout, SearchResultsView through `SheetPalette.destructive` — all 5 hardcoded warm-red sites collapsed to the one adaptive token.
- [x] Add `pipOuterRing` token + 0.8pt cream ring outside the numbered pips. Clear in light mode, cream @ 0.55 in dark — block-color stroke now lifts off the dark sheet.
- [ ] Verify on device: sheet readability, trash button visibility, callout readability (on-device test)
- [ ] Spot-check light-mode against current visual (must not regress) — on-device test



## Follow-up (2026-05-23, post-first-pass)

User on-device feedback: text contrast fixed, but the **destructive buttons** are still hard to read. Two distinct sub-bugs:

1. **Cut-out SF Symbols** (`plus.circle.fill`, `checkmark.circle.fill`) — the inner glyph is a *hole* in the filled circle. Applying `.foregroundStyle(destructive)` makes the whole symbol red; the glyph just shows whatever's *behind* it. In dark mode that's the dark sheet, so the glyph looks empty.
2. **Trash icons** — single-color symbols. The dark-mode destructive at (225, 90, 58) had similar luminance to the warm-sepia sheet — both warm, both dim. Plus the existing `.opacity(0.85)` reduced contrast further.

### Fixes

- Switched cut-out symbols to **palette rendering** with explicit `.foregroundStyle(.white, destructive)` — the inner glyph is now an actual white layer, not a transparent hole.
- Lifted dark-mode `destructive` from (225, 90, 58) → (245, 130, 100) — warm-coral territory. Keeps the warm-brand feel but separates from the warm-sepia sheet luminance-wise.
- Dropped the `.opacity(0.85)` on the two trash icons in `TripBottomSheet`.

Surfaces touched: `SearchResultsView` fast-add "+", `TripBottomSheet` active-trip checkmark, `TripBottomSheet` 'New Trip' "+", trash buttons on waypoint and trip rows.



## Round 3 — destructive buttons get the same colored-disc treatment

User feedback after round 2: +/✓ are 'top notch and beautiful' but trash and 'Remove' text 'still not divisible.'

The root cause was the asymmetry: +/✓ have visual weight (colored disc + white inner glyph), trash/Remove are just colored monochrome shapes with no anchor — they fight the warm sepia sheet in dark mode.

Fix: extend the same pattern (`colored disc + white inner symbol`) to the destructive buttons:

- TripBottomSheet waypoint trash → red/coral disc background, white trash icon.
- TripBottomSheet trip-row trash  → red/coral disc background, white trash icon.
- StopCallout 'Remove' button → red/coral disc around the trash icon (smaller, 28pt to match the action-item visual rhythm); 'Remove' label below gets bumped to bold weight for additional emphasis.

Light mode now also benefits — destructive actions read more clearly across both themes.



## Round 4 — split destructive (red) from additive (warm coral)

User feedback after round 3: the trash and 'New Trip' buttons now look IDENTICAL — both warm-orange discs with white inner glyphs. Two problems:
1. Trash no longer reads as 'remove' — iOS users expect RED for destructive.
2. The + (additive) and trash (destructive) being the same color is semantically wrong AND confusing.

The mistake was using ONE token (`destructive`) for two semantically distinct concepts. Split them:

- **`SheetPalette.destructive`** is now a proper red — light (200, 45, 45), dark (235, 80, 80). True 'danger' hue, no orange tilt.
- **`SheetPalette.accentWarm`** carries the previous warm-coral values — used for additive/affirmative actions (+, +, 'Add to trip'). Keeps the warm-paper brand identity.

Re-routed call sites:
- SearchResultsView fast-add '+'   → `accentWarm`
- TripBottomSheet 'New Trip' '+'   → `accentWarm`
- PreviewCallout 'Add to trip'     → `accentWarm`
- TripBottomSheet trash (waypoint) → stays on `destructive` (now red)
- TripBottomSheet trash (trip row) → stays on `destructive` (now red)
- StopCallout Remove               → stays on `destructive` (now red)
- AddedToTripToast 'removed'       → stays on `destructive` (now red)
- TripBottomSheet active checkmark → unchanged (uses per-trip color)

Now trash buttons say 'danger' and + buttons say 'add' at a glance.
