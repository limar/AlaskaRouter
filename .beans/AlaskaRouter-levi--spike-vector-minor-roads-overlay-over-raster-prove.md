---
# AlaskaRouter-levi
title: 'Spike: vector minor-roads overlay over raster (prove no double-draw, judge overzoom)'
status: in-progress
type: task
priority: normal
created_at: 2026-06-10T12:32:00Z
updated_at: 2026-06-10T13:20:10Z
parent: AlaskaRouter-7avb
---

## Why
Roads are core (this is a road-router app) and OTM hides minor classes (unclassified/service/track) until z13-14 -- below anything we render (pack maxzoom z11). Goal: bring the MISSING (minor) roads to the map WITHOUT raster-deeper bloat ([[r1cf]]) and WITHOUT double-draw (a hard user constraint -- "avoid at any cost").

## The load-bearing invariant -- makes double-draw structurally impossible
EXACTLY ONE layer owns each OSM road class. Always.
- Raster z11 today draws the MAJOR set (motorway..tertiary + links).
- Vector overlay draws ONLY the MINOR set (unclassified, residential, service, track, path, footway...).
- Disjoint sets => no road is ever painted twice. The forbidden config (same class in both layers) is simply never built.
- Small step = partition at minor/major (NO re-render). Big leap = partition at all/none (raster re-rendered roads-free, [[f7tt]]). Same code; the partition line just slides.

## Spike plan (prove, then proceed -- user wants visual confirmation first)
- [x] Toolchain: **tippecanoe 2.79 (felt fork)** + osmium, both brew. (tilemaker is no longer in homebrew; tippecanoe emits PMTiles directly from `osmium export` GeoJSON -- even leaner.) Source: the laptop's existing build-places Alaska PBF (2026-05-16).
- [x] Extent: Dalton corridor bbox -151,67..-148,69 (Coldfoot/Wiseman -> Atigun -> Galbraith -> Toolik/Sag River).
- [x] Emit minor-roads-ONLY PMTiles: tools/vector-roads-spike/build-corridor.sh -> **341 KB** for the WHOLE corridor z8-14 (432 features: 151 track, 133 path, 91 service, 23 unclassified...). The byte-cost argument, made flesh.
- [x] 4 MapLibre line layers in style-base.json (track dashed brown / path dotted / casing+fill white-gray for unclassified-residential-service), source minzoom 8, DISPLAY minzoom 9-10 (the free knob). Bundled as minor-roads-spike.pmtiles (gitignored, rebuilt by the script).
- [x] VERIFY AID produced. Anchors: Galbraith camp road (~6.7 km unpaved unclassified, 68.478,-149.494) + airstrip services; **Toolik Lake Road** (68.625,-149.561) + camp service roads; Coldfoot cluster (Airport Rd/Coldfoot Rd, 67.25,-150.19); Old Dalton Highway (67.805,-149.82); Sag River Camp Road (68.76,-148.87).
- [x] SIMULATOR verified (2026-06-10): Galbraith + Toolik screenshots show the missing roads, native-looking, drawn ONCE. Double-draw disproven by construction AND observation: the raw z11 raster tile (pmtiles tile 11/173/482) contains ZERO minor roads, so every minor road on screen is vector-only. App launches/renders normally.
- [ ] USER eyeball on the real iPhone: roads look native? styling/widths to taste? perf on device? (then decide ship-as-is vs big leap)

## Open UX fork -- judge IN the spike, do not answer from the old screenshot
When to show / how far to allow zoom. Today the app PROHIBITS zoom past z11 because overzoomed RASTER looked bad. BUT that verdict was on the OLD base (contours + labels -- the worst overzoom offenders). Dropping contours ([[xymz]], [[f7tt]]) + crisp vector roads on top likely changes it. Re-judge: raster source maxzoom stays 11 (softens gracefully -- relief is smooth), view maxzoom opens to ~13, vector roads stay crisp throughout. Decide from the new screenshot.

## Related
[[qp29]] decision (this realises Option 3 / hybrid). [[f7tt]] Track A: vibrant + contourless raster re-render (runs in parallel). [[r1cf]] the raster-deeper path we are NOT taking for the main pack. [[6ihk]] labels ride these same vector rails later.


## Note: the zoom cap to revisit
Today's z11 zoom-in cap was set by [[5h4y]] ("Limit map zoom-in to pack's max zoom -- no ugly upscaling"). The open UX fork above = whether the contourless base lets us raise that cap (raster softens, vector roads stay crisp). If yes, 5h4y gets relaxed.


## "How early do roads appear?" is a FREE knob, not a render stage (2026-06-10)
Minor roads come from the VECTOR overlay, not the raster -- so their appearance zoom is the MapLibre layer `minzoom`, a live style value (slide z9/z10/z11 on the phone, no rebuild). Decision: generate the vector roads tileset with low-zoom HEADROOM (emit from ~z8 in the tilemaker config -- low-zoom vector tiles are tiny/simplified, ~free), then tune the DISPLAY minzoom by eye. Contrast: in raster this question costs a full re-render; in vector it's a slider -- a point for the architecture. Only real cost of going earlier is CARTOGRAPHIC (clutter / sub-pixel meaninglessness at low zoom) -- judge by eye. Invariant still holds (minor classes only -> no double-draw at any zoom).

## Spike status (2026-06-10)

WIRED END-TO-END, simulator-verified. Implementation: `tools/vector-roads-spike/build-corridor.sh` (extract -> filter minor classes -> tippecanoe -> installs minor-roads-spike.pmtiles into Resources); style-base.json got the `minor-roads` vector source + 4 line layers right above the basemap; ExpeditionMapView substitutes `__MINOR_ROADS_URL__`; pbxproj bundles the (gitignored) pmtiles. Also added `initialCenter` LaunchArg (pairs with `initialZoom`) so screenshot runs can pin any camera -- used for the Galbraith/Toolik proofs.

DISPLAY-minzoom note: track/casing/fill at 9, path at 10 -- slide to taste, zero rebuild.

Remaining: user judgment on real device + styling taste pass; the overzoom (>z11 cap, [[5h4y]]) verdict deliberately WAITS for Track A's contourless base ([[f7tt]]).
