# Handoff: Alaska Router — Expedition Planner (iOS)

## Overview

Alaska Router is an **offline-first expedition planner and personal annotated atlas** for motorcycle / overlanding travel, mocked here for iPhone (modern iOS). It is *not* a turn-by-turn navigation app — navigation is delegated to external apps (Apple Maps, Google Maps, Waze, Organic Maps). The product feels like a digital paper map: clean field-tool typography, semi-transparent floating UI, soft-blur materials, muted topographic palette, hand-style annotations.

The bundled prototype uses a fictional **Dalton Highway, Alaska** trip (Fairbanks → Yukon River Camp → Coldfoot → Atigun Pass → Galbraith Lake → Deadhorse) as a content stand-in. Replace this with real map tiles and POI data when wiring up to a real geo backend.

## About the Design Files

The files in this bundle are **design references created in HTML** — interactive prototypes showing the intended look, motion, and behavior. They are not production code to copy directly.

The task is to **recreate these designs in the target codebase's existing environment**. For iOS this is most naturally **SwiftUI** (the design leans heavily on iOS 17/18+ idioms — Dynamic Island, glass materials, sheet presentation detents). If implementing cross-platform, **React Native** or **Flutter** are reasonable; the styling tokens below port cleanly.

Map rendering: the prototype uses a hand-built SVG topographic placeholder. **In production, use a real map renderer** — MapLibre Native, Mapbox, or Apple MapKit — with a custom style that approximates the paper-topo look (see "Map Style" below). All other UI (search bar, bottom sheet, POI card, annotation editor, controls) is genuine product UI to be implemented as designed.

## Fidelity

**High-fidelity.** Colors, typography, spacing, animation timing, and interaction behavior are all final. Pixel-perfect replication is expected for the chrome (search bar, sheet, cards, controls). The map itself is a stand-in — match the *visual style*, not the SVG geometry.

## Files

- `index.html` — entry point; loads React 18 + Babel from CDN and the JSX modules below
- `app.jsx` — top-level `App` component, state management, `SearchBar`, `FloatingControls`, `PoiCard`, `AnnotEditor`, `AnnotInstruction`
- `map.jsx` — `ExpeditionMap` (the hand-built SVG topo placeholder), POI data (`POIS`), default annotations, two color themes (`paper`, `field`)
- `sheet.jsx` — `BottomSheet` with three snap points, block-grouped stops list with drag-reorder, `BlockHeader`, `StopRow`
- `ios-frame.jsx` — iPhone bezel/Dynamic Island/status bar/home indicator chrome (replace with native chrome on a real device)
- `tweaks-panel.jsx` — design-time tweaks panel (does not ship in production)

To open the prototype: load `index.html` in a modern browser. All interactions work without a backend.

---

## Screens & States

The product is a single full-bleed screen — the **map is the primary interface and occupies almost the entire viewport**. Floating UI overlays the map. Five distinct UI states drive the experience:

### 1. Idle map (search bar expanded)

- Full-bleed map fills the screen.
- Floating search bar pinned to the top, full-width, with a search icon, placeholder ("Search Alaska, the Yukon…"), and a profile chip.
- Beneath the bar: a horizontally scrolling row of category filter chips — `Fuel`, `Camp`, `Visitor`, `Pass`, `Lodging`, `Water`.
- Right side: zoom in/out pair (oversized), then a smaller utility stack (Layers, Recenter, Annotate).
- Bottom: collapsed sheet showing trip name, stat strip (Distance / Stops / Longest fuel gap / Offline).

### 2. Map after pan/zoom (compact search bar)

- The moment the user pans or zooms, the search bar **morphs**: its geometry animates (left/top/width/height/border-radius) over 440ms with a custom iOS curve into a **40×40 circular puck centered just below the Dynamic Island**.
- The input, profile chip, and category chips cross-fade out as the bar shrinks.
- An 11px trip-name pill ("Dalton Highway — North") drops in below the puck with an 80ms delay, preserving active-trip context.
- Tap the puck → bar expands back to full state.

### 3. POI tap → contextual bottom card

- Tap any POI marker on the map → bottom sheet is replaced by a **contextual card** (240ms slide-up animation).
- Card contains: kind label · POI name (serif) · sub-line · metadata strip (Coords / Elevation / From last) · primary CTA "Add to trip" (filled with accent color) · three secondary actions (Navigate · Note · Save) · external-nav hint.
- "Add to trip" inserts the POI into the route in geographic order (south → north).
- "Navigate" should open a sheet to choose between Apple Maps, Google Maps, Waze, Organic Maps.

### 4. Annotation creation on map

- Tap the pencil icon in the floating controls → an instruction toast appears at top ("Tap the map to drop a note") with cancel button. Map cursor becomes crosshair.
- Tap the map → editor card slides up containing a textarea (rendered in Caveat handwritten font, in the currently selected ink color) and a 5-swatch ink color picker (amber / ink blue / pine green / plum / graphite). "Drop note" CTA confirms.
- Confirmed annotation renders directly on map: handwritten text with a translucent highlighter swatch behind each line, plus a curved arrow pointing from the label to the anchor point. Slight random rotation (-3° to +3°) gives a hand-placed feel.

### 5. Bottom sheet — expanded (editable route)

- Sheet has **three snap points**: 120px (collapsed) / 380px (half) / 640px (expanded). Drag the handle to resize; releases snap to the nearest detent.
- **Stops are grouped into named blocks** (replacing day-by-day itinerary planning).
- Each block has a colored numbered chip (#1, #2, …), optional name (auto-fallback like "Coldfoot → Galbraith Lake"), and a stop count.
- Stops are **indented under their block header** (24px left padding). Each stop row: drag handle · numbered pip in block color · POI name (serif) · kind hint · split button (start new block here) · remove button.
- Drag a stop by its handle to reorder it. Tap the split icon next to any stop to start a new block at that stop. Tap the merge icon on a block header to fold it back into the previous block.

### 6. Waypoint icons (numbered route stops on map)

POIs that are part of the active trip are rendered as **numbered waypoint markers** in the block's color. The icon style is configurable, with four built-in options:

- **Pin** — classic teardrop map pin, number in the head. Most cartographic.
- **Stamp** — hexagonal field-tool badge, color outline, number centered. Pairs with the paper theme.
- **Dot** — solid colored circle with white number. Minimal; best for long routes with many stops.
- **Tag** — the POI's kind glyph (fuel pump, tent, pass…) plus a small numbered chip floating top-right. Preserves both category and sequence.

**Counter-scaling for readability.** Waypoints are UI markers, not cartographic features — they must stay readable at every zoom level. Each marker is wrapped in `transform="translate(x y) scale(1/zoom)"`, so its visual size stays constant on screen across the [0.7, 2.4] zoom range. The selection pulse and label offsets are positioned in screen pixels (inside the counter-scaled group), so they don't drift off the icon as the map zooms.

---

## Layout & Geometry

**Device target:** iPhone 15 Pro / Pro Max class, 402pt logical width, 874pt height (the prototype's iPhone frame). All measurements below are in pt unless noted otherwise.

### Top region (search + status)

- Dynamic Island: 126×37 centered, top: 11
- Search bar (expanded): `top: 58, left: 14, right: 14, height: 48, border-radius: 16`
- Search bar (compact puck): `top: 56, left: 181, width: 40, height: 40, border-radius: 999`
- Trip-name chip (only when compact): `top: 102, centered, padding: 3px 10px, font-size: 11`
- Category chips row: `top: 114, left: 14, right: 14, gap: 6`, chips `padding: 6 13`, `border-radius: 999`, `font-size: 13`

### Right-side floating controls

- Zoom pair container: `right: 12, top: 150, width: 50, border-radius: 16` (single rounded pill containing both buttons)
- Each zoom button: `50 × 52, divider 0.5px between them with 8px horizontal margin`
- Utility stack: `right: 12, top: 280, gap: 8`. Each button is a 44×44 round-square (`border-radius: 14`)

### Bottom sheet

- Full-width, anchored to bottom, `border-radius: 22 22 0 0`
- Snap heights: `[120, 380, 640]`
- Drag handle: 38×5 capsule, centered, 8px top padding, `rgba(60,50,20,0.22)`
- Internal scroll only active at expanded snap point

### POI card

- `left: 12, right: 12, bottom: 18, border-radius: 22, padding: 14 16 16`
- Slide-up animation: `translateY(20px) → 0`, `opacity 0 → 1`, 240ms cubic-bezier(.22,.9,.27,1)

---

## Design Tokens

### Colors

**UI / chrome (paper variant — default):**

| Token | Value | Usage |
|---|---|---|
| `--surface-paper` | `#fcfaf4` (86% alpha for sheet) | Bottom sheet, POI card |
| `--surface-search` | `rgba(255,253,247,0.78)` | Search bar background |
| `--text-primary` | `#1a1a1a` | Body text, primary labels |
| `--text-secondary` | `rgba(60,50,20,0.6)` | Sub-labels, hints |
| `--text-tertiary` | `rgba(60,50,20,0.45)` | Section headers (uppercase small) |
| `--divider` | `rgba(0,0,0,0.07)` | Hairlines |
| `--field-tint` | `rgba(255,255,255,0.6)` | Inputs, secondary buttons |

**Map themes:** see `MAP_THEMES` in `map.jsx`. Two themes are exposed via Tweaks (`paper` warm parchment / `field` cool Apple-Maps-leaning). Key paper-theme map colors:

| Token | Value | Usage |
|---|---|---|
| `bg` | `#efe5cf` | Map base |
| `land` | `#f3ecd6` | Default ground |
| `forest` | `#aebd87` + stipple | Taiga south of Brooks |
| `tundra` | `#e3dabf` + dots | Coastal plain north of Brooks |
| `rock` | `#cdb791` + hatch | Mountain mass |
| `water` | `#a9c5d3` | Rivers and lakes |
| `road` | `#2c2a25` | Highway centerline |
| `road-casing` | `#f5ecd4` | Wider highway underlay |
| `contour` | `rgba(146,114,72,.42)` | Elevation lines |

**Block accent palette** (route segments):

```
#0369a1  — block 1
#ea580c  — block 2
#7c3aed  — block 3
#15803d  — block 4
#b91c1c  — block 5
#a16207  — block 6
```

Blocks wrap modulo length. Tweaks panel exposes 5 alternative accent palettes for the primary CTA.

**Annotation ink colors:** `#c2410c #1d4ed8 #15803d #9333ea #1a1a1a`

**Semantic colors:**

| State | Color |
|---|---|
| Warning (fuel-gap stat) | `#9a3412` |
| Success (offline-ready stat) | `#166534` |

### Typography

Three font families, in priority order:

1. **System font** (`-apple-system, "SF Pro Text", system-ui, sans-serif`) — UI chrome, buttons, sub-labels, stats values when in chrome
2. **Source Serif 4** (Google Fonts) — POI names, sheet titles, stat values, map labels, region names. Use 400/500/600 weights.
3. **Caveat** (Google Fonts) — Map annotations only. Use 500/600/700.

**Scale (in pt):**

| Token | Family | Size | Weight | Line-height | Letter-spacing |
|---|---|---|---|---|---|
| Search input | System | 16 | 400 | — | — |
| Trip name (sheet header) | Serif | 22 | 600 | 1.15 | — |
| POI card title | Serif | 20 | 600 | 1.15 | — |
| POI name in stop row | Serif | 15 | 600 | — | — |
| Sheet section header | System | 11 | 700 | — | `1.2` UPPERCASE |
| Tiny label (uppercase) | System | 10 | 600 | — | `0.5` UPPERCASE |
| Stat value | Serif | 15 | 600 | — | — (tabular numerals where shown) |
| Body / row hint | System | 11.5–13 | 400–500 | — | — |
| Map region label | Serif | 18–26 | 500 | — | `4–6` UPPERCASE |
| Map place label (major POI) | Serif | 11–13 | 600 | — | — |
| Map place label (minor POI) | Serif | 10 | 500 | — | — |
| Map water label | Serif italic | 9–13 | 400 | — | — |
| Handwritten annotation | Caveat | 18 (svg) / 22 (input) | 600 | 1.15 | — |

Numbers in stops and stats should use **tabular numerals** (`font-variant-numeric: tabular-nums`).

### Spacing

Roughly an 8pt grid with half-step exceptions where iOS conventions dictate. Common gaps: `4 / 6 / 8 / 10 / 12 / 14 / 16 / 18 / 24`.

### Border radius

| Element | Radius |
|---|---|
| Sheet top / POI card | 22 |
| Search bar (expanded) | 16 (or 999 in "pill" variant) |
| Search bar (compact puck) | 999 |
| Float button square | 14 |
| Zoom container | 16 |
| Chip / pill button | 999 |
| Stops list card | 16 |
| Inline field / textarea | 11–12 |
| Block-color chip in header | 6 |

### Shadows

| Element | Shadow |
|---|---|
| Bottom sheet | `0 -8px 30px rgba(60,40,10,0.10), inset 0 -0.5px 0 rgba(0,0,0,0.07)` |
| POI card | `0 -8px 30px rgba(60,40,10,0.10), 0 10px 40px rgba(60,40,10,0.14)` |
| Search bar (expanded) | `0 1px 1px rgba(0,0,0,0.04), 0 8px 28px rgba(60,40,10,0.10)` |
| Search puck (compact) | `0 4px 14px rgba(60,40,10,0.20), 0 1px 2px rgba(0,0,0,0.06)` |
| Float buttons | `0 4px 14px rgba(60,40,10,0.10)` |
| Zoom container | `0 6px 18px rgba(60,40,10,0.14), 0 1px 2px rgba(0,0,0,0.04)` |
| Primary CTA glow | `0 6px 16px ${accent}40` (40 = 25% alpha) |

### Blur materials

All floating UI uses backdrop blur: `backdrop-filter: blur(20–28px) saturate(170–180%)`. On iOS native, this maps to `.ultraThinMaterial` / `.thinMaterial`.

---

## Components

### SearchBar

A single morphing element with two states. Animates `left / top / width / height / border-radius / padding / gap` simultaneously over **440ms** with `cubic-bezier(.62, .04, .32, 1)`. Child elements (input, profile chip, category chips) cross-fade with their own 220–280ms easing.

**Behavior:**
- Expands automatically when the sheet is collapsed AND map has not been panned/zoomed AND no input focus
- Collapses to a puck the instant the user pans, zooms, or expands the sheet past collapsed
- Tap puck → returns to expanded state (focus input)

### FloatingControls

Right-side overlay with two groups:

1. **Zoom pair** (`top: 150`): single rounded container holding `+` and `−` buttons (50×52 each, hairline divider). Disabled state at 32% opacity when min/max reached.
2. **Utility stack** (`top: 280`): three 44×44 glass buttons stacked vertically with 8pt gap — Layers / Recenter / Annotate.

Zoom math keeps the viewport center pinned on the same map coordinate when zoom factor changes:
```
mx = (W/2 - panX) / oldZoom
my = (H/2 - panY) / oldZoom
newPanX = W/2 - mx * newZoom
newPanY = H/2 - my * newZoom
```
Zoom multiplier per click: `×1.4` in, `×1/1.4` out. Clamp: `[0.7, 2.4]`.

### BottomSheet

Drag-resizable sheet with three snap points `[120, 380, 640]`. Pointer-drag on the handle adjusts height live; on release, snap to the nearest detent with a 320ms `cubic-bezier(.22, .9, .27, 1)` animation. While dragging, transition is disabled so the sheet tracks the finger 1:1.

**Contents per snap:**
- Collapsed (120): trip header + stat strip only
- Half (380): adds route list (block-grouped, indented stops)
- Expanded (640): same as half, scrollable internally

**Block grouping logic:**
- Route is a flat array of stops, e.g. `[{id, blockBreak?}, …]`
- `blockBreak: true` on a stop means a new block starts at that stop
- First stop is implicitly the start of block 1 (never carries the flag)
- Walk the route incrementing `blockIdx` whenever you hit a break

**Stop drag-reorder:** pointer-capture on the row's drag handle. Compute target index from cumulative pointer-Y / row-height. While dragging, the row gets a faint accent tint and `z-index: 2` so it overlays neighbors.

**Block header:** colored chip with block number, editable name (click-to-edit; placeholder = auto-name like "Yukon River Camp → Coldfoot"), stop count subtitle, optional merge button (rolls block back into previous).

### PoiCard

Replaces the sheet when a POI is selected. Slide-up entrance:
```
@keyframes poi-slide-up {
  from { transform: translateY(20px); opacity: 0 }
  to   { transform: none;            opacity: 1 }
}
```
Duration 240ms `cubic-bezier(.22, .9, .27, 1)`. The "Add to trip" CTA toggles to a neutral "✓ On this trip" state with no shadow once added.

### Map (placeholder → real renderer)

The bundled SVG topo is a **content stand-in only**. In production, render with a vector map library and a custom style that approximates this palette and layering:

- **Base land**, gentle tundra/forest tint zones
- **Faint lat/lon graticule** at low opacity (`rgba(80,60,30,0.06)`)
- **Forest stipple** pattern (organic dots, ~14pt tile) and **tundra dot** pattern (~22pt tile, sparser)
- **Rock hatch** fill for mountain masses (35°-rotated 0.4pt strokes)
- **Contour lines** every ~100ft equivalent, 0.55–0.9pt, brown
- **Roads:** 6pt light casing → 2.6pt dark centerline → 1.2pt dashed gravel center (only on Dalton-class roads)
- **Rivers:** width-scaled by importance (Yukon ~9pt, tributaries ~3.5pt, small streams ~1.6pt) with darker 0.5pt edge stroke
- **Paper grain overlay** (SVG fractal noise filter) at 2.5% opacity for paper variant only
- **Compass rose** top-right and **scale bar** bottom-left, both subdued

**Map labels degrade gracefully when zoomed out** (the brief calls this out explicitly):
- Major POIs (city, fuel, pass, park): always render
- Mid POIs (camp, landmark, viewpoint): render at normal+ density
- Minor POIs (town): render at high density only
- Below threshold, labels become small dots or are clustered

A `labelDensity: 'low' | 'normal' | 'high'` setting controls thresholds.

### Annotations

Each annotation has:
```
{ id, text, color, x, y, anchor: {x, y}, rot: -3..+3 }
```
Render with two pieces:
1. **Highlighter swatches** behind each line of text (color at 18% opacity, ~16pt tall, 2pt corner radius)
2. **Handwritten text** in Caveat at 18pt, color at 92% opacity, lines stacked at 18pt line height
3. **Curved arrow** from label origin to anchor: `M label Q midX midY-18 anchor`, with a small triangle arrowhead

---

## Interactions & Behavior

### Search bar morph

- Trigger: user pans, zooms, or expands the sheet past collapsed
- Reverse: user re-centers (resets pan/zoom), focuses puck, or returns to idle state
- Always animates — never snaps

### Pan and zoom

- **Pan:** pointer-down on the map → pointer-capture → translate `pan.x, pan.y` by delta/zoom
- **Zoom:** buttons only in this prototype; production should also support pinch (UIPinchGestureRecognizer / native gesture)
- Both pan and zoom should set a "user has interacted" flag → triggers search-bar morph

### Bottom sheet drag

- Pointer-down on the 38×5 handle starts drag; live height updates as `startH + (startY - clientY)`
- Pointer-up: snap to closest of `[120, 380, 640]` with 320ms ease
- Velocity-based projection (Apple Maps does this) is a nice-to-have, not implemented in the prototype

### Stop reorder

- Pointer-down on stop row's drag handle → mark row as `reordering` (visual highlight, raised z-index)
- Live shift based on `dy / 52`; reorder route array on every detected swap so the list shifts under finger
- Block memberships are *positional* — when a stop moves above/below a block boundary, it joins the new block automatically (the `blockBreak` flag stays with its original stop, not with the moved one)

### Block split / merge

- Tap split icon on a stop row → set `blockBreak: true` on that stop → new block starts there
- Tap merge icon on a block header → clear `blockBreak` on the first stop of that block → block folds into previous
- First stop in the route can never carry a `blockBreak` flag

### Annotation creation

- Tap pencil → enter "adding annotation" mode (instruction toast, crosshair cursor, POI taps suppressed)
- Tap map → place anchor at tap point, place label 100pt left and 30pt up of anchor by default, open editor
- Save → push annotation with random rot ∈ [-3°, +3°] and a unique id
- Cancel anywhere → exit mode without saving

### POI tap

- Tap POI → set selectedPoi → POI gets a pulsing ring (animated `r 9 → 14, opacity 0.85 → 0`, 1.4s loop)
- Sheet collapses to make room for the card
- Tap × on card or tap empty map → clear selection

---

## State Management

Top-level state in `App`:

| State | Type | Purpose |
|---|---|---|
| `pan` | `{x, y}` | Map pan offset (pre-zoom) |
| `zoom` | number | Map scale factor (0.7–2.4) |
| `hasPanned` | bool | Flips search bar to compact |
| `snap` | 0 \| 1 \| 2 | Bottom sheet snap index |
| `route` | `Stop[]` | Ordered route stops |
| `blocks` | `Block[]` | Block metadata indexed by ordinal |
| `selectedPoi` | string \| null | POI id currently shown in card |
| `addingAnnot` | bool | "Tap to place annotation" mode |
| `draftAnnot` | `{x, y, anchor}` \| null | Anchor placed, editor open |
| `annotations` | `Annotation[]` | All saved annotations |
| `searchFocused` | bool | Search input focused |

**Stop:** `{ id: string, blockBreak?: boolean }`
**Block:** `{ name: string, color: string }`
**Annotation:** `{ id, text, color, x, y, anchor: {x, y}, rot }`

### Data fetching (production)

This prototype is fully client-side. In production:
- POIs: tile-based query against a geo backend (fuel stations, campgrounds, NPS visitor centers, named landmarks)
- Map tiles: vector tiles from MapLibre/Mapbox or rasterized USGS/OSM
- Offline regions: pre-pack tile bundles per geographic region; surface a region-picker UI (designed in brief but not in this prototype)
- Trip + annotations sync: per-user, last-write-wins should be fine for personal planning

---

## Assets

- **Fonts:** Google Fonts — `Source Serif 4` (weights 400/500/600), `Caveat` (weights 500/600/700). Bundled in production app rather than CDN'd.
- **Icons:** all custom SVGs inlined in components. No icon library dependency. Reproduce in SF Symbols where possible for native iOS.
- **Map data:** the hand-built SVG paths in `map.jsx` are placeholders — use real geo data.
- **No raster assets.** Profile chip is a CSS gradient with initials; replace with real user avatar.

---

## Notes for Implementer

1. **Map first.** The map is 80% of the experience. Get a real renderer with a custom paper-topo style live before iterating on the chrome. Apple MapKit's `MKMapConfiguration` with a custom overlay set is one option; MapLibre Native gives more styling control.

2. **Glass materials are non-negotiable.** Every floating element uses backdrop blur. On SwiftUI: `.background(.ultraThinMaterial)`. Without blur, the design falls flat.

3. **Search bar morph is the signature interaction.** Match the 440ms duration and `cubic-bezier(.62, .04, .32, 1)` curve exactly — the brief explicitly references Safari's address-bar behavior. iOS native: animate frame and corner radius together inside a `withAnimation(.timingCurve(0.62, 0.04, 0.32, 1, duration: 0.44))`.

4. **Use SF Pro Text for chrome and Source Serif 4 for content.** This serif-for-content choice is what gives Alaska Router its "expedition atlas" feel — don't drop it in favor of an all-system-font implementation.

5. **Sheet detents** map directly to SwiftUI's `.presentationDetents([.height(120), .medium, .large])` or a custom 3-stop implementation.

6. **Drag-reorder for stops** — SwiftUI's `.onMove` modifier works on lists but doesn't show smooth row-shift animation across block boundaries. For high fidelity, implement a custom drag overlay with manual index calculation as the prototype does.

7. **Annotations as overlays:** in MapKit / MapLibre, annotations should be `MKAnnotationView` / native overlay nodes with custom rendering. Render the highlighter swatch and Caveat text into a small UIView/CALayer; render the arrow as a separate `CAShapeLayer`. The slight rotation (-3° to +3°) is what sells the hand-placed feel — keep it.

8. **External navigation handoff.** "Navigate" should `UIApplication.shared.canOpenURL` each of Apple Maps / Google Maps / Waze / Organic Maps, then present an action sheet of installed options.

9. **Light only.** No dark mode in this design. (The brief said "paper-map feel" only.) If dark is added later, the cool `field` map theme is a good starting point.

10. **The tweaks panel does not ship.** It's a design-time tool for comparing variants (paper vs field map theme, accent palettes, label density, annotation visibility, search-bar shape, waypoint icon style). Pick one default in production — recommended: paper theme, accent #ea580c/#9a3412, normal label density, annotations on, rounded search bar, pin waypoint style.
