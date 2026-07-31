---
# AlaskaRouter-dzhp
title: 'Callout rework: title legibility, then visual balance'
status: completed
type: bug
priority: high
created_at: 2026-07-27T23:28:04Z
updated_at: 2026-07-31T22:01:21Z
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
- [x] Check the taller callout still sits correctly relative to its pin

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
- [x] Decide: match the existing slate blue, or introduce per-category colour for both
- [x] Align icon size and placement between the two callouts — measured, deliberately NOT aligned
- [x] Extract the duplicated category -> SF Symbol map

## Icon map extracted (2026-07-30)

It was **three** copies, not two: `StopCallout`, `PreviewCallout` and `SearchResultsView` each carried the same 24-case switch. Verified byte-identical by diffing the extracted key/symbol token streams (50 tokens each, all three match), so the extraction is provably behaviour-neutral.

Now `CategorySymbol.name(for:)` in `AlaskaRouter/Search/CategorySymbol.swift`, beside `CategoryLabel` which already centralises the human-readable name for the same keys.

`PlaceIcons` deliberately keeps its own separate mapping — it drives the *map markers*, needs a filled/outline pair per category for the visual-variant harness, and makes different cartographic choices on purpose (peak → triangle, settlement → hollow circle). Merging it would change what the map draws.

Still open, all needing design discussion: title legibility, the red accent, and the icon colour/size/placement alignment.

## Title legibility: shipped (2026-07-31)

Rule (user's choice, from rendered evidence in `spikes/D_callout`): **one line at full size whenever the name fits; otherwise drop to 75% and wrap up to 4 lines, ellipsizing the last.** Implemented as `CalloutTitle` in `AlaskaRouter/UI/CalloutTitle.swift`, used by both StopCallout (17pt semibold) and PreviewCallout (16pt bold).

Verified in the real app, not the spike: `Chena River Lakes Project and Recreation Area` (44 chars) now reads in full in StopCallout; short names are untouched at full size.

### Findings that reading the code would not have produced
- **`lineLimit(n)` alone silently no-ops in this layout.** Any wrapping needs `fixedSize(horizontal: false, vertical: true)`. The first spike build had the 'fixed' variant rendering pixel-identical to the bug.
- **`fixedSize()` on the single-line ViewThatFits candidate is what makes the heuristic work at all** — it forces the candidate's ideal width to the whole string, which is how ViewThatFits knows to reject it.
- **A wrapped title needs `.firstTextBaseline`** or the category icon drifts to the vertical middle and detaches from the name.
- **85% is a dominated option.** Measured: it takes the same number of lines as no shrink at all, so it costs type size and buys no vertical space. 75% vs 'keep full size' is a genuine either/or; 85% is neither.

### Rejected: title full-width below the button column
Explored because the '…'/'✕' column costs the title 72pt of 272pt. Moving the title to its own row below them bought ~46% more width and fit even a 45-char control name in 2 lines at full 17pt. Rendered well, but the user chose to keep the title beside the buttons at this stage. Spike variants E/F remain in `spikes/D_callout` if we revisit.

### Follow-up noticed while verifying
In PreviewCallout the fallback lands at 12pt (16 × 0.75), which is exactly the size of the `Park` / category line beneath it — the two differ only by weight. It reads acceptably because of the bold + primary colour, but the title is no longer dominant by size. Worth a look during the red-accent / visual-balance pass.

## Icon: settled (2026-07-31)

**Colour — slate blue in both.** `CalloutIcon` in `AlaskaRouter/UI/CalloutIcon.swift`. This closes the field report (grey on a stop, coloured on a POI).

**Per-category colour was built and rejected on rendered evidence.** The obvious move — borrow `PlaceIcons.color(for:)`, which already tints the map markers — does not transfer. Those values assume the cream paper basemap; the callout is `.thinMaterial` and picks up the map colour beneath it, so warm browns go muddy on a green-tinted card and nearly vanish on a warm one. It fails worst on the commonest case: `settlement_major` is #3A2A18, near-ink by design so towns top the paper map's label hierarchy, which in a callout reads as *no colour at all* — the very complaint that opened this bean. `PlaceIcons.color` is back to private with that finding recorded in place, so the next person doesn't retry it. Per-category is still possible, but needs a callout-specific palette (brighter, saturated, a real hue for settlements), not this one.

**Size and placement — deliberately NOT aligned.** Both alternatives were built and measured:
- Leading column in StopCallout costs 32pt (22pt icon + 10pt spacing) of 272pt content width. The title goes 2 lines → 3, and the distance line truncates again ("132 km from Higher Groun…") — reintroducing the failure this bean exists to remove.
- Inline in PreviewCallout drops the icon 18pt → 12pt, where it reads as a bullet rather than the subject of the card. PreviewCallout is 320pt with a 16pt title and only a ✕ (no "…"), so it can afford the column that StopCallout cannot.

The mismatch is each callout fitting its own width budget, and the two are never on screen together. User's call: leave as-is. The A/B harness (`calloutIconLayout`) has been removed now that both halves are decided.

**Pin clearance (the old unchecked todo).** Both callouts are positioned proportionally (`Spacer`/callout/`Spacer`/`Spacer`, upper third), not by a fixed offset from the pin, so there is no hardcoded height to break. Measured on the real 2-line callout: **~11pt of clearance** to the pin. Each extra title line adds ~7.6pt downward, so a 3-line title leaves ~3pt and a 4-line title would overlap the pin. Not reachable with real data (the longest real name is 44 chars → 2 lines) but it is the bound on `CalloutTitle`'s 4-line allowance. Worth revisiting only if a name that long ever appears.

## Accent: shipped, bean complete (2026-07-31)

**"Open in…" now takes `SheetPalette.accentWarm` with white text**, the same fill and capsule shape as PreviewCallout's "Add to trip". Both callouts now carry one matching warm primary action, which is what restores the "small red paint" the callout lost when AlaskaRouter-pmnd demoted the ghost-red Remove capsule.

Chosen from four rendered candidates on the real app. Rejected: warming the "STOP n OF m" label, and warming the label plus the category icon. User: leave the label and the icon alone.

**Recorded for the record, not as an objection:** this reinstates a full-width coloured capsule — the shape pmnd removed for dominating the callout — now carrying a constructive action rather than a destructive one. If it ever reads as too dominant in the field, the lighter variants are in this bean's history and take minutes to restore.

**Also found while doing this.** The palette already encodes a colour grammar nobody had written down: the committed waypoint pin draws at (0.78, 0.32, 0.20), which is *exactly* `SheetPalette.accentWarm`, and the preview pin at (0.20, 0.40, 0.65), which is *exactly* `CalloutIcon.slateBlue`. Warm = a committed stop, blue = a preview. Worth knowing before anyone picks a new colour for either callout.

## Summary of Changes

1. **Shared category → SF Symbol map extracted** to `CategorySymbol` — it was three byte-identical copies (StopCallout, PreviewCallout, SearchResultsView), verified identical before extracting.
2. **Title legibility fixed** via `CalloutTitle`: one line at full size when the name fits, else 75% across up to four lines. Long Alaska names read in full for the first time.
3. **Icon colour unified** to slate blue in both callouts, closing the field report. Per-category was built and rejected on evidence.
4. **Icon size/placement deliberately left per-callout**, with the measurements showing why aligning them regresses one side or the other.
5. **Warm "Open in…"** restores the accent.

All A/B harnesses added along the way (`calloutIconStyle`, `calloutIconLayout`, `calloutAccent`) have been removed now the decisions are made. Spike lives on at `spikes/D_callout`.
