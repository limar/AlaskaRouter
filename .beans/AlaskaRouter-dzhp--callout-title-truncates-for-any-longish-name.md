---
# AlaskaRouter-dzhp
title: 'Callout rework: title legibility, then visual balance'
status: todo
type: bug
priority: high
created_at: 2026-07-27T23:28:04Z
updated_at: 2026-07-30T22:08:28Z
parent: AlaskaRouter-36of
---

Field-tested Alaska trip, July 2026. Stop and place names ellipsize constantly — "Galbraith Lake Campground" shows as "Galbraith Lake Ca…". Alaska names are long ("Marion Creek Campground", "Arctic Interagency Visitor Center", "The Inn at Coldfoot Camp"), so this is the common case, not the edge case.

## Where
- `StopCallout.swift` — title is `.font(.system(size: 17, weight: .semibold))` with `.lineLimit(1)`, inside a callout capped at `maxWidth: 300` (just widened from 260 for AlaskaRouter-pmnd, which bought one or two characters — not a fix).
- `PreviewCallout.swift` — same pattern at 16 pt, capped at 320.
- The header "…" menu (pmnd) and the ✕ button both eat into the available width.

## Options to discuss
- **Two lines with `lineLimit(2)`.** Simplest, and callout height is not precious — it floats over the map. Risk: the callout's height becomes variable, which affects how it is positioned relative to the pin.
- **Adaptive size via `minimumScaleFactor`.** Keeps one line and a fixed height; long names just get smaller. Apple Maps does this. Risk: a very long name gets genuinely small, and the type scale stops being a scale.
- **Both**: `lineLimit(2)` + a modest `minimumScaleFactor(0.85)` — wrap first, shrink only if two lines still overflow. This is the usual iOS answer.
- **Widen the callout further.** Cheapest, least effective; 320 is already near the practical limit on a 393 pt-wide phone.

Recommendation to beat: `lineLimit(2)` plus `minimumScaleFactor(0.85)`, and check the callout still positions sensibly when it grows a line.

## Todo
- [ ] Render the options against the worst real names in the trip
- [ ] Agree and implement across StopCallout AND PreviewCallout (keep them coherent)
- [ ] Check the taller callout still sits correctly relative to its pin

## Widened into a full callout rework (2026-07-27)

The user reviewed the shipped AlaskaRouter-pmnd change (Remove demoted to the header "…", "Open in…" promoted to the primary slot) and judged it **"better than it was, but imperfect"** — specifically, the callout *"became a bit boring when it lost the small red paint"*. The ghost-red Remove capsule was carrying visual interest that nothing replaced.

So this bean absorbs the whole callout rather than just the title:

- **Title legibility** — the original scope. Long Alaska names ellipsize constantly.
- **Bringing some red back.** Possibly the Delete button itself, possibly just an accent. The user explicitly wants to revisit this *after* the title question is settled, since how the title resolves (one line vs two, shrunk vs wrapped) changes how much room and visual weight is left over.
- **Whether Remove returns to the surface** — it currently lives only in the header menu. If the layout regains room, a small red affordance may earn its place back, without returning to the full-width capsule that dominated the callout.

Sequence matters: settle the title first, then judge the balance, because the title's resolution determines the space available.

Applies to both `StopCallout` and `PreviewCallout` — they must stay coherent.

## Also in scope: the category icon differs between the two callouts (2026-07-30)

Field report: tapping a city / airport / peak gives a coloured icon in the callout's top-left, but tapping a **waystop** gives a grey one. Should be coloured everywhere.

Verified — and it is three differences, not one:

| | `StopCallout` (a trip stop) | `PreviewCallout` (a place/POI) |
|---|---|---|
| colour | `.secondary` — grey | `Color(red: 0.20, green: 0.40, blue: 0.65)` — slate blue |
| size | 12 pt | 18 pt |
| placement | inline, just before the title | 22x22 leading element, its own column |

**Check the expectation before implementing:** the POI icon is not actually multi-coloured — it is a *single* slate blue for every category. So "colourful everywhere" is satisfied by matching that blue; but if what is meant is *per-category* colour (tent green, fuel orange, peak grey-brown), that is a bigger change and should apply to both callouts. `PlaceIcons` already carries per-category colour for the map markers, so there is a palette to borrow rather than invent.

**Cleanup to fold in:** both files carry their own ~24-case `category -> SF Symbol` switch, byte-identical today (checked). Two copies that must agree is how they stop agreeing. Extract one shared mapping — natural home is beside `CategoryLabel`, which already centralises the human-readable name.

## Todo
- [ ] Decide: match the existing slate blue, or introduce per-category colour for both
- [ ] Align icon size and placement between the two callouts
- [x] Extract the duplicated category -> SF Symbol map

## Icon map extracted (2026-07-30)

It was **three** copies, not two: `StopCallout`, `PreviewCallout` and `SearchResultsView` each carried the same 24-case switch. Verified byte-identical by diffing the extracted key/symbol token streams (50 tokens each, all three match), so the extraction is provably behaviour-neutral.

Now `CategorySymbol.name(for:)` in `AlaskaRouter/Search/CategorySymbol.swift`, beside `CategoryLabel` which already centralises the human-readable name for the same keys.

`PlaceIcons` deliberately keeps its own separate mapping — it drives the *map markers*, needs a filled/outline pair per category for the visual-variant harness, and makes different cartographic choices on purpose (peak → triangle, settlement → hollow circle). Merging it would change what the map draws.

Still open, all needing design discussion: title legibility, the red accent, and the icon colour/size/placement alignment.
