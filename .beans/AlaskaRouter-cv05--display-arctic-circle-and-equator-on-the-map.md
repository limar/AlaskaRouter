---
# AlaskaRouter-cv05
title: Display Arctic Circle and Equator on the map
status: completed
type: feature
priority: low
created_at: 2026-05-20T20:20:13Z
updated_at: 2026-06-09T12:44:55Z
parent: AlaskaRouter-xtua
---

Draw the Arctic Circle (lat 66.5634°N) and the Equator (lat 0°) as gentle latitude reference lines on the basemap. The Arctic Circle is iconic for Alaska — crossing it is a photo-stop landmark for any northbound trip — and the Equator gives global orientation when zoomed all the way out. Both should feel like atlas lines: thin, dashed, labeled, low-key.

## Why

The Arctic Circle (66.5634° N) is the single most iconic latitude landmark for any Alaskan trip — it's where every Dalton Highway traveler stops to photograph the "Arctic Circle" wooden sign and decide whether they're committing to Deadhorse or turning back. Showing it on the map turns it from "a place name to remember" into "a line you can see, follow, and orient to."

The Equator pairs naturally — it's the global orientation cue when fully zoomed out (z=0..3), the moment when you can't read any place labels.

## Likely implementation

Both lines are constants, never change. Encode as a small GeoJSON `LineString` (Arctic Circle: full 360° at lat 66.5634; Equator: full 360° at lat 0) and load via a vector source like the anchor labels.

Style as `LineStyleLayer`:
- `line-dasharray`: e.g. `[6, 4]` — atlas-style dashed
- `line-width`: thin (0.8pt at low zoom, no need to scale up)
- `line-color`: warm sepia for Arctic Circle (`#7a5e2b`), softer grey for Equator
- `line-opacity`: zoom-interpolated, fade in around z=2 and stay visible

Plus a `SymbolStyleLayer` for labels:
- `text-field`: "Arctic Circle" / "Equator"
- `symbol-placement: line` (text follows the line itself)
- `text-letter-spacing: 0.25`, small caps optional

## Considerations

- Globally drawn — the Arctic Circle is interesting around Alaska too, not just at the precise crossing. Lines should not be Alaska-only.
- Tropics (Cancer / Capricorn) and Antarctic Circle would naturally follow — defer to a follow-up if there's appetite.

## Checklist

- [x] ~~Author `lat-lines.geojson`~~ — embedded the two LineStrings as INLINE GeoJSON in `style-base.json` (constants; no separate file/substitution needed)
- [x] Add `lat-lines` source + `lat-line-{arctic,equator}` line layers + `lat-label-{arctic,equator}` symbol layers to `style-base.json` (inserted between basemap and label-region)
- [x] ~~Wire `__LAT_LINES_URL__`~~ — N/A with inline data. Instead added `LatLines.apply(_:to:)` (mirrors `MapLabelSizing`) called from the unsafe hook to apply live Tweaks.
- [x] Verified dashing reads on-device: z5 (Dalton corridor) and z1 (world skeleton)
- [x] Verified the "ARCTIC CIRCLE" spaced-caps label reads cleanly across the Dalton/Yukon-Flats band at z5

## Implementation notes

- **Approach: inline GeoJSON (Option A).** Source + 4 layers declared statically in `style-base.json` — zero new bundled files, zero URL substitutions, no interaction with the imperative route/marker hot path. Ships standalone even if Tweaks never runs.
- **Live iteration via Tweaks** (full playground): new "Reference lines" collapsible section in `TweaksPanel` backed by 6 `TweaksStore` props — Arctic color palette (5 earth/sepia), Equator color palette (4 greys), line width, dash style (solid/fine/atlas/dotted), label-size multiplier, Equator-label on/off. Applied at runtime by `LatLines.apply` (fingerprint-guarded, mirrors `MapLabelSizing`). Converged values become the shipped defaults.
- **Zoom behavior:** label text-size zoom-interpolated; label opacity fades to 0 at far zoom (Arctic by ~z2, Equator by ~z1 → no label at z0). Both lines drawn at all zooms.
- **Defaults** (mirrored in both `style-base.json` and `TweaksStore.Defaults`): Arctic sepia #7a5e2b, Equator grey #8a8275, width 0.9pt, atlas dash [6,4], label mult 1.0, Equator label ON.
- **Verified:** builds clean; app runs without crashes (earlier launch crashes were the gitignored `alaska-pack.pmtiles` being absent from the worktree — pre-existing env issue, not this change); route/markers/place-labels/sheet all unaffected.

## Tuning iteration 1 (look-and-feel)

User feedback on first cut: sepia invisible on the vibrant relief; a single line color can't survive both deep-ocean blue and desert/mountain. Resolved by switching to a **casing** model rather than chasing a magic color.

- **Casing model:** each line and label is now a CASING (soft cream, wider, under) + CORE (dark, over) pair → self-contrasting, legible over ocean AND terrain. Deterministic; no blend-mode/XOR tricks (MapLibre iOS has no line blend modes anyway).
- **New defaults:** Arctic core = Charcoal brown #4a3b2b; Equator core = Charcoal #5a564e; width 1.4pt; dash = Dotted; label size ×1.25.
- **Labels:** camelCase "Arctic Circle" / "Equator" (was ALL CAPS). Added a **Label weight** tweak — pseudo-bold via same-color halo (only Noto Sans Regular glyphs ship offline; true bold would need bundling Bold/Medium glyph PBFs). allow-overlap + ignore-placement = true so place labels never knock it out; symbol-spacing 220 so a copy is reliably on-screen (fixes the 'drifts off-screen on zoom' report).
- Verified on-device: Equator reads over deep Pacific; Arctic Circle label centered + repeating at z5; no crashes.

### Label-on-zoom logic — RESOLVED
- Repeating along-line label (a single fixed label is impossible for a globe-spanning line — its center is at lon 0, off in Africa).
- Density exposed as a **Label spacing** tweak (default 220pt); collisions no longer drop it (allow-overlap + ignore-placement).
- Size grows gently z3→z10 then constant; opacity fades out at far zoom.

## Summary of Changes

Shipped the Arctic Circle + Equator reference lines, fully tunable via Tweaks, on-device verified, zero regressions.

**Approach:** inline GeoJSON source + static layers in `style-base.json`; runtime look-and-feel via `LatLines.apply` (mirrors `MapLabelSizing`, fingerprint-guarded, called from ExpeditionMapView's unsafe hook).

**Visibility (the hard part):** a single line color can't survive deep-ocean blue AND desert/mountain. Solved with a **casing model** — each line/label = soft cream casing (wider, under) + dark core (over), self-contrasting → deterministic ~99% visibility. XOR/blend rejected (MapLibre iOS has no line blend modes); ocean/land segmentation rejected (brittle, partial).

**Files:**
- `AlaskaRouter/Resources/style-base.json` — `lat-lines` source (2 LineStrings) + 8 layers (casing+core × line/label × arctic/equator).
- `AlaskaRouter/Map/LatLines.swift` (new) — runtime applier; palettes; dash-matched casing.
- `AlaskaRouter/Map/ExpeditionMapView.swift` — hook call.
- `AlaskaRouter/UI/TweaksStore.swift` + `TweaksPanel.swift` — "Reference lines" section: Arctic/Equator color, width, dash, label size/weight/spacing, Equator-label toggle.

**Defaults:** Arctic core charcoal-brown #4a3b2b, Equator core charcoal #5a564e, 1.4pt, dotted, label ×1.25, weight 0.5 (pseudo-bold), spacing 220.

**Known limitation / follow-up candidate:** label weight is pseudo-bold (same-color halo) because only Noto Sans Regular glyphs ship offline; real bold would need bundling Medium/Bold glyph PBFs.
