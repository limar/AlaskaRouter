---
# AlaskaRouter-h113
title: Trip export/import as file (lossless round-trip)
status: completed
type: feature
priority: high
created_at: 2026-06-14T14:48:55Z
updated_at: 2026-06-14T16:25:14Z
blocking:
    - AlaskaRouter-56kj
---

Reinstalls during development wipe SwiftData, destroying created trips. Add lossless trip export/import to a file so trips survive reinstall, transfer between device and simulator, and can be attached to bug reports for a specific trip.

## Design (agreed 2026-06-14)

### Source-of-truth vs derived (the core framing)
- **Tier 1 — export always (not recomputable):** Trip {id,name,colorRaw,createdAt,notes}; Waypoint[] {id,order,lat,lon,label,category,modeRaw}; BlockSeparator[] {id,afterWaypointID}.
- **Tier 2 — export as OPTIONAL cache (not recomputable offline):** snap geometry — Trip.snappedRoute* whole-trip blob + per-pair RouteSegment rows + routerVersion.
- **Tier 3 — NEVER export, always recompute:** blocks, per-block colors (colorForBlock), routeRibbons / onion offsets / fallback dashing, pendingPairIndices. All are pure derivations of (waypoints + separators + snap). Storing them = staleness risk.

### Format
- Flat JSON, custom extension `.akrtrip` + exported UTI (e.g. com.alaskarouter.trip) so Files/AirDrop/share-sheet route it back into the app.
- Envelope: { schemaVersion, appVersion, exportedAt, trip{}, waypoints[], separators[], routingCache? }.
- routingCache: { routerVersion, wholeTrip{polylineEncoded,geometryKey,computedAt}, segments[{fromLat,fromLon,toLat,toLon,polylineEncoded,distanceMeters,durationSeconds,computedAt}] }.

### Rules
- DTO layer (TripDTO/WaypointDTO/SeparatorDTO/RoutingCacheDTO, Codable) — NOT Codable on the @Model classes. Decouples wire format from SwiftData schema so migrations don't break old files. Versioned via schemaVersion.
- routingCache optional + self-validating: importer keeps it only if routerVersion == RoutingEngineVersion.current, else drops and re-snaps. Exact exported coords mean tripGeometryKey (lat,lon@5dp) recomputes identically -> imported trip shows real road geometry instantly, OFFLINE, on the simulator. Pending legs derived as "pairs with no cached segment".
- Import-as-copy by default: fresh UUIDs, afterWaypointID remapped consistently. Optional "preserve IDs / replace existing" mode for debug round-trip.

### Decisions locked
- Container: flat JSON now (re-architect to zip later if annotations/photos [AlaskaRouter-3es6] need to ride along).
- Snap cache: included as optional block.
- Interop (Markdown-for-Notes, GPX/GeoJSON): DEFERRED to a separate one-way "Share" bean — not part of round-trip.

## Todos
- [x] Define DTO layer + schemaVersion envelope (TripDTO etc.)
- [x] Encode/decode: Trip <-> DTO mapping (Tier 1 + optional Tier 2)
- [x] Export action: ShareLink + ExportedTripFile (Transferable) -> AirDrop/Files/Messages
- [x] Register custom UTI + extension; handle inbound open (.onOpenURL + .fileImporter)
- [x] Import: insert as copy (fresh UUIDs, remap separator refs); optional preserve-ID/replace mode
- [x] Import validates/keeps routingCache only on routerVersion match, else re-snap
- [x] Verify imported trip renders real geometry offline (covered by cache-validity unit test; full UI render needs the gitignored tile pack, not run here)
- [x] Tests: round-trip equality (Tier1), derived recompute (blocks/ribbons), cache-key validity, ID remap, routerVersion mismatch -> drop cache (7 tests, all green; full suite 96/96)

## Summary of Changes

Lossless `.akrtrip` trip export/import shipped.

**New files**
- `AlaskaRouter/Data/TripDocument.swift` — versioned Codable DTO envelope + `export(_:context:)` and `importTrip(into:mode:)`. Tier 1 always; Tier 2 (routing cache) optional & self-validating; Tier 3 never serialized (re-derived).
- `AlaskaRouter/Sharing/TripFileTransfer.swift` — `UTType.alaskaRouterTrip` (`dev.alaskarouter.trip`, ext `.akrtrip`, conforms public.json) + `ExportedTripFile: Transferable` for ShareLink + filename sanitizer.
- `AlaskaRouter/Sharing/TripFileImport.swift` — security-scoped URL reader shared by fileImporter and onOpenURL.
- `Tests/TripDocumentTests.swift` — 7 tests.

**Edits**
- `AlaskaRouter/Info.plist` — UTExportedTypeDeclarations + CFBundleDocumentTypes.
- `AlaskaRouter/UI/TripBottomSheet.swift` — replaced rename pencil with an ellipsis Menu (Rename / Export via ShareLink / Import via fileImporter) + import-error alert.
- `AlaskaRouter/App/RootView.swift` — `.onOpenURL` imports a tapped/AirDropped `.akrtrip` and makes it active.

**Key property:** because exported coordinates are exact, `tripGeometryKey` (lat,lon@5dp) recomputes identically on import, so the embedded snap cache stays valid — an imported trip shows real road geometry instantly, even offline. ID-remap keeps separator anchors and block splits intact in copy mode; preserveID replaces in place.

**Deferred (separate bean):** one-way human/interop share (Markdown-for-Notes, GPX/GeoJSON).

## Live verification (2026-06-14, simulator)

- App builds, installs and launches on iPhone 17 Pro sim with the offline pack. Renders the map + seeded trip.
- E2E import: hand-crafted `.akrtrip` (Parks Hwy waypoints + separator + indigo color + routingCache.wholeTrip = real demo-route polyline) opened via the app's actual `.onOpenURL` handler (`xcrun simctl openurl`). Result: active trip switched to "IMPORTED Parks Hwy", 5 stops / 2 blocks / indigo chip — separator + color round-tripped through the real file path. No crash.
- Offline routed-geometry render CONFIRMED: at z9 over the Nenana canyon the imported trip draws the curvy snapped highway line (follows the river/road), not straight chords — proving the embedded snap cache is used after import with no network.
- Tests now 11 in TripDocumentTests (added on-disk round-trip via TripFileImport + garbage-file rejection). Full suite green.

### Asset note (not a code bug)
The styleURL guards in ExpeditionMapView fatalError if a required bundled asset is missing. This worktree was missing `minor-roads-spike.pmtiles` (all `*.pmtiles` are gitignored, so they do not propagate to worktrees) — copied it in from the main checkout to run. A from-scratch worktree needs BOTH `alaska-pack.pmtiles` and `minor-roads-spike.pmtiles` in AlaskaRouter/Resources to launch.

## Document icon branding (2026-06-14, follow-up in same bean)

Replaced the white schematic default with the app icon for the `.akrtrip` type (user-approved, kept the system share sheet as-is — no supported API to hide the apps row / exclude self, confirmed via Apple dev forums).

Two levers:
- **Info.plist** `CFBundleDocumentTypes` → added `CFBundleTypeIconFiles` = [TripDocumentIcon-320, TripDocumentIcon-64]. Branded icon for `.akrtrip` in Files / Mail.
- **TripBottomSheet** ShareLink preview → `SharePreview(trip.name, image: tripFilePreviewImage)`, loading the bundled app-icon PNG. Fixes the share-sheet header thumbnail directly.
- Icon PNGs generated from AppIcon.png (1024) via `sips` at 320 + 64, placed in AlaskaRouter/Resources (bundle root). `*.png` is NOT gitignored, so these are committed.

Verified: build succeeds; both PNGs + CFBundleTypeIconFiles present in the built .app; UTI intact; full suite 98/98 green. NOT visually verified: the rendered share-sheet thumbnail / Files icon — the export sheet needs a tap (computer-use was declined), so the icon render is unconfirmed pending a manual tap.

## App-icon white-corner fix (2026-06-14, folded into h113 per user)

Root cause (diagnosed, not a sim glitch / not our code): AppIcon.png shipped with an alpha channel + baked-in rounded corners (transparent corners), violating Apple\047s opaque-full-bleed-square rule. iOS overlays its own squircle mask → transparent corners composited on white → white slivers in the share-sheet apps row (and anywhere iOS masks the icon, incl. home screen). Pre-existing; surfaced by the export sharing UI.

Fix (quick flatten, user-approved): flattened AppIcon.png onto sampled paper cream (#FDD390) with `-alpha off` → opaque full-bleed square, colors preserved. Regenerated TripDocumentIcon-320/64 from the now-opaque source (they had inherited the alpha).

Verified: AppIcon + both doc icons now hasAlpha:no; build OK; suite 98/98; springboard render shows clean rounded corners with NO white slivers (simctl screenshot, headless). Apps-row entry uses the same masking path so it is fixed by the same mechanism (not separately screenshot-able without a tap / computer-use).

Residual (accepted): a faint trace of the baked rounding may remain just inside iOS\047s mask. Proper full-bleed redrawn art would remove it — deferred unless it bothers in practice.

## CORRECTION (2026-06-14) — supersedes the "App-icon white-corner fix" section above

That app-icon fix did NOT work and its verification was wrong. The share-sheet APPLICATIONS-ROW icon still shows white corners; only the document/file icon is correct. The flatten never reached the compiled app icon (runtime corners were white, not the cream fill; bundled icon still hasAlpha:yes), and verification was done on the springboard (blue wallpaper) instead of the share-sheet apps row (white bg) where the defect is obvious.

Resolution: reverted AppIcon.png via `git checkout` (back to original). The app-icon defect is split out to its own bug bean **AlaskaRouter-56kj** with a correct diagnosis and proper-fix path. h113 keeps ONLY: export/import + document-icon branding (CFBundleTypeIconFiles + SharePreview + TripDocumentIcon PNGs), which work. h113 stays completed.
