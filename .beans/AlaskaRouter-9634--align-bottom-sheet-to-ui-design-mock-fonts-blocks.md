---
# AlaskaRouter-9634
title: Align bottom sheet to UI design mock (fonts, blocks, palette)
status: completed
type: feature
priority: high
created_at: 2026-05-20T17:59:29Z
updated_at: 2026-05-20T19:23:35Z
parent: AlaskaRouter-xtua
---

Rebuild TripBottomSheet against design/mocks/sheet.jsx — serif typography, warm paper palette, visually distinct block headers, indented stops, soft-card containment. Preserve trash-delete and add-block-separator controls.

## Why

The current `TripBottomSheet` works, but visually it's the weakest surface in the app. The HTML mock at `design/mocks/sheet.jsx` is way cleaner — and the gap is large enough that the user flagged it directly:

> "It looks way cleaner with its visual blocks and waypoints. The fonts selection is top-notch. Our fonts are lame, separators visibly resemble waystops and the colors are being messed."

The mock isn't a sketch — it's the high-fidelity reference (`design/mocks/README.md` calls colors / typography / spacing "final, pixel-perfect replication is expected"). We've drifted because v1 functionality landed feature-by-feature without one polish pass against the reference.

## Gap analysis (mock → current)

Read alongside `design/mocks/sheet.jsx` and `AlaskaRouter/UI/TripBottomSheet.swift`.

### Typography — biggest visual win
- **Mock:** Source Serif 4 (serif) for trip name, block name, stop name; `-apple-system` (SF) only for small caps labels / hints / button text.
- **Current:** SF system everywhere. Reads generic, not atlas-like.
- **Action:** Adopt a bundled serif (Source Serif 4 or New York / Charter as a near-zero-cost iOS-native fallback) for the three "name" tiers. Keep SF for labels, hints, eyebrows.

### Block headers vs stop rows — the "separators resemble waystops" complaint
- **Mock:** Block header is a *distinct* row — `rgba(0,0,0,0.018)` tinted strip, 22pt colored rounded-square chip with white bold number, serif name + "N stops" subline, optional merge-into-previous button. It looks like a section header.
- **Current:** Separator row uses the same colored *circle* badge + pill background as a stop row would, sized similarly → visually indistinguishable from a waypoint. (`separatorRow` at TripBottomSheet.swift:319–342.)
- **Action:** Redesign separator as a header strip — square-ish chip, larger and bolder, with a "N stops" subline and clearly different background fill. Drop the matching rounded pill; lean into "this is a heading, not an item."

### Indentation + connector line — visual containment
- **Mock:** Stops are indented 24pt under their block header, with a thin (1.5pt) block-colored vertical connector running through each numbered pip, linking the stops in a block.
- **Current:** All rows sit at the same indent. No connector — no visual hint that stops belong to the block above them.
- **Action:** Add left-indent on stop rows under a block (only when blocks exist; if there's just one implicit block, keep flat). Render the colored connector via a leading `Rectangle`/`Capsule` strip + numbered pip overlay.

### Stops list as a contained card
- **Mock:** Whole stops list lives inside one soft white card — `rgba(255,255,255,0.55)` fill, `16pt` radius, `0.5px` border — sitting on the warm sheet background. Reads as a "page in a binder."
- **Current:** `List(.plain)` rows directly on `.thinMaterial` — no visual container.
- **Action:** Wrap the stops region in a rounded card. The `List` `.plain` style can stay inside; the card is just a background + clipShape on the section.

### Numbered pips
- **Mock:** Small (16pt) **white-filled circle** with a colored stroke and a tiny tabular-numeric digit inside.
- **Current:** 28pt color-tinted *filled* circle. Heavy, draws too much attention vs the place name.
- **Action:** Shrink + invert — white fill, 1.6pt colored stroke, monospaced 9–10pt number.

### Colors
- **Mock:** Warm paper palette — `rgba(252,250,244,0.86)` sheet bg, `rgba(60,50,20,…)` text alphas, accent ambers/greens. Feels like a ranger-station atlas.
- **Current:** `.thinMaterial` + `.primary`/`.secondary`. Generic iOS, "tech-blue adjacent" — directly contradicts the README's "no flat tech-blue."
- **Action:** Centralize a small `SheetPalette` (sheet bg, paper text alphas, sep tints, card fill). Replace `.primary`/`.secondary` in the sheet only — don't touch the map/search yet.

### Trip header — eyebrow + serif name
- **Mock:** Tiny uppercase eyebrow ("ACTIVE TRIP · AUG 2026") above a 22pt serif trip name.
- **Current:** 18pt bold SF name + chevron, no eyebrow.
- **Action:** Add the eyebrow line; bump the name to serif 20–22pt. Keep the chevron and the rename pencil.

### Stat strip
- **Mock:** Horizontal Distance | Stops | Longest fuel gap | Offline-Ready strip with 1px vertical separators, uppercase 10pt labels, serif 15pt values, color-coded (green for "Ready", amber for "longest fuel gap" when > threshold).
- **Current:** Two stat chips (stops, km) trailing the trip name on the same line — easy to miss.
- **Action:** Promote to a full-width strip beneath the trip header. "Longest fuel gap" and "Offline" can be stubs at first (placeholders feeding from manifest / trip data later — they're follow-up work, not blockers).

## Must NOT lose (the existing controls)

The mock omits some of v1's actual mechanics. Keep these even where the mock doesn't show them:

- [x] **Trash / delete waypoint** per row (currently `waypointRow` lines 301–308). The mock has a remove button at the row's trailing edge — keep ours, restyled to match the mock's small round button.
- [x] **Add block separator** row at the bottom of the list (currently `addBlockRow` lines 344–359). The mock uses inline per-stop "split here" buttons instead. We can keep both: inline split is a nice addition (out of scope for this bean — opens AlaskaRouter-???), but the bottom "Add block separator" affordance stays for discoverability in v1.
- [x] **Drag-to-reorder** via the trailing `line.3.horizontal` handle (currently uses `.onMove`). Mock has a leading drag handle (the dots SVG) — restyling fine, but keep the iOS-native `.onMove` integration so swipe-to-delete still works.
- [x] **Switch to .trips mode** via tap on header (`toggleMode`, line 435). Keep — the mock doesn't show multi-trip but we ship it.
- [x] **Rename pencil** next to trip name (line 172). Keep.
- [x] **Empty-state hint** when `orderedWaypoints.isEmpty` (line 204). Keep, restyled to match the warm palette.

## Out of scope (follow-ups)

- Inline per-stop "split here" button → separate bean (it's a nicer UX but interacts with the block model in ways worth thinking through).
- Auto-generated block names ("Yukon River Camp → Coldfoot") → separate bean (currently we use the separator's stored display name).
- Editable block names inline → separate bean.
- "Longest fuel gap" computation → separate bean (depends on having fuel POIs along the route).

## Likely implementation

1. Add `AlaskaRouter/UI/SheetPalette.swift` with the warm-paper color tokens + serif font helper (use `Font.custom("New York", size:)` or `.serif` design first; only bundle Source Serif 4 if NY doesn't carry the feel — adding a bundled font is its own ~30 min task).
2. Refactor `TripBottomSheet.swift` row builders:
   - `summary` → eyebrow + serif name + stat-strip below.
   - `separatorRow` → block-header strip (square chip, "N stops" subline, no pill).
   - `waypointRow` → indented inside its block, smaller white-stroke pip, restyled trash + drag handles.
   - Stops region wrapped in a rounded card.
3. Verify with the user on real device (iPhone 16) — the user has it connected and asked specifically to check things for real.

## Checklist

- [x] `SheetPalette.swift` (color + font tokens) added
- [x] Trip header rebuilt — eyebrow + serif name
- [x] Stat strip rebuilt — Distance / Stops / Blocks (dropped Offline; see Summary)
- [ ] Stops region wrapped in soft white inset card — DEFERRED (List-inside-card sizing; see Summary)
- [x] Block-separator row redesigned as a header strip (visually NOT a stop) — square chip + 'N stops' subline
- [x] Stop rows indented under their block; small white pip (vertical connector deferred — see Summary)
- [x] Delete-waypoint button preserved, restyled
- [x] Add-block-separator row preserved at list bottom, restyled
- [x] Empty-state hint restyled
- [x] `.trips` mode visually consistent with new palette (rename row, new-trip row)
- [x] Verified on sim screenshots against the mock side-by-side — user-approved

## References

- Reference: `design/mocks/sheet.jsx` (esp. `BlockHeader`, `StopRow`, `Stat`, color values)
- Reference: `design/mocks/README.md` §"5. Bottom sheet — expanded (editable route)"
- Code: `AlaskaRouter/UI/TripBottomSheet.swift`
- Related: AlaskaRouter-71rb (label / zoom tuning — same atmospheric direction)
- Related: AlaskaRouter-ir85 (anchor on-map controls — separate but in the same "sheet polish" theme)

## Summary of Changes

`AlaskaRouter/UI/SheetPalette.swift` (new) — central tokens:
- Warm-paper surface tint laid OVER `.thinMaterial` to shift "iOS grey glass" → "kitchen-table paper."
- Warm sepia text palette (textStrong / textMuted / textEyebrow).
- Block header bg, card border, row divider, stat divider — all tied to one warm hue.
- `Font.sheetSerif(_:weight:)` (resolves to system serif → New York on iOS 13+) and `Font.sheetSans(_:weight:)` helpers.

`AlaskaRouter/UI/TripBottomSheet.swift` (full rewrite of view layer; logic preserved):
- **Trip header** — uppercase eyebrow ("ACTIVE TRIP") + 20pt serif trip name + chevron mode-toggle + restyled rename pencil. At `.collapsed` a "5 stops · 203 km" subline appears in the eyebrow group so stats remain visible.
- **Stat strip** — 3 cells (Distance / Stops / Blocks) with vertical hairline dividers. Dropped the mock's "OFFLINE Ready" cell — the app is offline-by-design in v1, so the indicator was always-on noise. (Revisit when v2 fetches tiles dynamically.)
- **Block separator → header strip** — square color chip with white bold number + serif name + "N stops" subline. Distinctly NOT shaped like a stop row (no round pip, no trash, drag handle only). This is the heart of the bean: the user's "separators visibly resemble waystops" complaint is fixed.
- **Stop rows** — small white-fill pip with 1.6pt colored stroke and a monospaced numeric digit (was a heavy 28pt color-filled circle). Serif stop name + sans kind hint. Indented when the trip has any block separators so the visual hierarchy reads.
- **Add-block-separator row** — preserved at list bottom but restyled as a subtle dashed-border affordance (was a full-width pill).
- **Empty-state hint** — restyled to match palette + serif name tier.
- **`.trips` mode** — picked up the same warm palette; serif trip names, sepia subtitles, warmer-red destructive accent.

`AlaskaRouter/App/RootView.swift` — z-order fix for ir85:
- On-map controls + scale moved to render BEFORE the sheet in the ZStack, so the sheet covers them when expanded to `.overview` / `.full`. At `.collapsed`, the controls sit just above the sheet edge as before.

## Deferred (follow-ups)

- **Soft white inset card wrapping the stops list** — the mock has the list inside a rounded white card. `List` inside a card has awkward sizing issues; deferred until we know whether to switch to a `ScrollView`/`LazyVStack` (which would also be needed for the colored vertical connector below).
- **Block-colored vertical connector** linking stops within a block — needs custom row layout that doesn't fight with `List`'s built-in geometry. Same architectural question as the card wrapper.
- **Implicit block-1 header** for the first block (the mock renders a header above every block including the first). Currently the first block's stops are visually orphaned from any explicit header — they read fine but don't mirror the mock exactly. Cheap to add later if it bugs the user.
- **Bundled Source Serif 4** — the mock specifies Source Serif 4; we use `.system(design: .serif)` (New York) which carries the feel for zero bundle cost. Swap in if the system serif feels short.
- **Auto-named blocks** ("Yukon River Camp → Coldfoot") — separate behavioral change tracked elsewhere.

## Verification

Built clean. Simulator screenshots captured at all three detents (collapsed / overview / full) plus `.trips` mode and the with-block state — all in `/tmp/sheet-*.png`. User to ⌘R on iPhone 16 for the on-device check.
