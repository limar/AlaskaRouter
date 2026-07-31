---
# AlaskaRouter-pq9g
title: 'Export preview snapshot flakily fails: ''Error parsing PMTiles directory'''
status: completed
type: bug
priority: normal
created_at: 2026-07-31T18:05:27Z
updated_at: 2026-07-31T19:48:27Z
---

`MLNMapSnapshotter` intermittently fails to read the bundled PMTiles archive while the live `MapView` is reading the same file. The completion handler returns:

```
Error Domain=MLNErrorDomain Code=6 "Error parsing PMTiles directory: map::at:  key not found"
```

When it fires, `TripPreviewRenderer` yields nil and the share sheet silently falls back to the app icon instead of the map thumbnail (AlaskaRouter-56kj). No crash, no user-visible error — just a worse preview.

## Evidence (measured 2026-07-31, iPhone 17 Pro sim, iOS 26.5)

Launch-time render (snapshot started synchronously in the same main-thread turn as `.onAppear`, i.e. before the MapView starts pulling tiles):

- **10 / 12 launches OK**

Deferred render (identical renderer, but the call wrapped in `Task { }` so the snapshot starts one main-thread turn later, after the MapView is loading):

- **1 / 12 launches OK**

Both call sites (spike dump + bottom-sheet preview) fail together when it happens, so it's per-launch, not per-snapshotter. Reproduce with:

```bash
xcrun simctl launch --console-pty booted dev.alaskarouter.AlaskaRouter -seedDemoTrip YES -spikePreview "63.07,-151.0"
```

## Why it matters beyond the launch render

`TripBottomSheet` also regenerates the preview from `.onChange(of: previewSignature)` — renaming a trip or changing its first stop re-renders while the map is fully live, which is exactly the ~1/12 regime. That path is probably failing almost every time today.

## Consequences already felt

This is why `TripPreviewRenderer` is still a completion-handler API rather than `async`: an async shape forces the call sites into a `Task`, which is the 1/12 timing. See the NOTE ON SHAPE comment at the top of AlaskaRouter/Sharing/TripPreviewRenderer.swift. Fixing this unblocks that cleanup.

## Todo
- [x] Found it: the contention is snapshotter-vs-snapshotter, not map-vs-snapshotter
- [x] Checked — the cache logic is identical in `main` and in our pinned ios-v6.26.0; no upstream fix exists yet
- [x] Decided: serialize renders (depth-1 newest-wins queue). Aliased archive URLs measured 0/12 and were rejected.
- [x] Re-measured: 44/44 serialized across the three harshest conditions; 12/12 on the shipping build in the original configuration
- [x] Revisited — serialization removes the timing constraint, so the async shape is now viable; kept the completion handler by choice (see AlaskaRouter-wq1q)

## Root cause (upstream: maplibre-native `pmtiles_file_source.cpp`)

Read the source at the tag we ship (`ios-v6.26.0`) — the cache logic is byte-identical to `main`.

`PMTilesFileSource::Impl` keeps two parallel structures with **no mutex** (single actor thread, but interleaved request chains):

```cpp
std::map<std::string, std::map<std::string, std::vector<pmtiles::entryv3>>> directory_cache;
std::map<std::string, std::vector<std::string>> directory_cache_control;  // LRU order
constexpr int MAX_DIRECTORY_CACHE_ENTRIES = 100;
```

`storeDirectory` desyncs them:

```cpp
directory_cache.at(url).emplace(key, pmtiles::deserialize_directory(data));  // NO-OP if key exists
directory_cache_control.at(url).emplace_back(key);                          // ALWAYS appends

if (directory_cache_control.at(url).size() > MAX_DIRECTORY_CACHE_ENTRIES) {
    directory_cache.at(url).erase(directory_cache_control.at(url).front());  // evicts a LIVE key
    directory_cache_control.at(url).erase(directory_cache_control.at(url).begin());
}
```

Two chains that miss the same directory *concurrently* both fetch and both store: the map gets one entry, the control vector gets two. Duplicates accumulate; once control passes 100, eviction erases a directory that is still live — including, sometimes, the one just stored.

The very next thing that runs is `getTileAddress`'s continuation:

```cpp
std::vector<pmtiles::entryv3> directory = directory_cache.at(url).at(
    url + "|" + std::to_string(directoryOffset) + "|" + std::to_string(directoryLength));
```

`std::out_of_range`. And because that continuation is invoked *inside* `getDirectory`'s `try`, the exception is mislabelled on the way out as `"Error parsing PMTiles directory: " + e.what()` — which is why the message names directory parsing when nothing was being parsed.

### Why our two consumers trigger it

Concurrent first-time misses on one url are the necessary condition. The live MapView's startup tile burst supplies them; MLNMapSnapshotter shares the same `PMTilesFileSource` (FileSourceManager hands out one instance per type+ResourceOptions) and therefore the same `directory_cache[url]`, so it roughly doubles the burst. That matches every measurement: worst when the snapshot starts mid-burst (1/12), better when it starts before the map gets going (10/12), and both call sites failing together in the same launch.

### Upstream fix (small)

```cpp
auto [it, inserted] = directory_cache.at(url).emplace(key, pmtiles::deserialize_directory(directoryData));
if (inserted) {
    directory_cache_control.at(url).emplace_back(key);
    if (directory_cache_control.at(url).size() > MAX_DIRECTORY_CACHE_ENTRIES) { /* evict */ }
}
```

(`directory_cache_control.at(url).back()` in `getDirectory` is also an unguarded `back()` on a possibly-empty vector.)

### Testable prediction, not yet run

If the model is right, a snapshot taken when the archive's directories are ALREADY cached takes the cache-hit path in `getDirectory` — no store, no eviction, no throw. So gating the render on map idle (rather than one turn after `.onAppear`, which is the worst possible moment) should measure 12/12. That is both the confirmation and a shipping mitigation, and it would fix the `.onChange(of: previewSignature)` regenerate path too.

## Approach vectors (ranked)

1. **Patch upstream + PR to maplibre-native.** The actual fix, ~4 lines. Then bump the pin when released, or build a patched xcframework locally (bazel; heavy but one-time).
2. **Gate the render on map idle (app-side, cheap).** Probabilistic, not a fix, but it targets the exact condition. Measure before believing it.
3. **Give the snapshotter its own url for the same archive** — a hardlink (`link()`, zero extra disk) referenced by a snapshot-only style. Different url = different inner map + control vector, so map and snapshotter stop compounding each other's bursts. Still probabilistic; combines with (2).
4. **Take MapLibre out of the preview path entirely.** Read the ~4-9 raster tiles for the preview straight out of the PMTiles archive with our own reader and composite them. Most work, but immune to all of the above and removes a whole failure surface from the export path.

## Experiment results (2026-07-31, iPhone 17 Pro sim, iOS 26.5)

Harness: one build, all conditions behind dev-only launch args (`spikePreviewMode`, `spikeSecondConsumer`, `spikeSerialize`, `spikeSeparateArchive`, `spikeBurst`). Success = the spike wrote its PNG. Uncommitted; the diff and per-run logs are in the session scratchpad.

| # | snapshot consumers | timing | variant | result |
|---|---|---|---|---|
| A | 1 | same turn as `.onAppear` | — | **12/12** |
| B | 1 | one turn later | — | **12/12** |
| C | 2 | same turn | — | 10/12 |
| D | 2 | one turn later (staggered) | — | **1/12** |
| E | 2 | one turn later | serialized | **12/12** |
| F | 2 | one turn later | aliased archive URLs | **0/12** |
| G | 2 | +5 s apart | — | 12/12 |
| H | 2 + burst of 5 | same turn | — | 6/12 |
| I | 2 + burst of 5 | same turn | serialized | **12/12** |
| J | 2 + burst of 5 | one turn later | serialized | **20/20** |

Serialized total: **44/44** across the three harshest conditions.

## Corrected mechanism

The earlier writeup blamed contention between the live MapView and the snapshotter. **That was wrong**, and two results kill it:

- **A/B: a single snapshotter never failed in 24 runs**, while the map was doing its full startup tile burst underneath. The map does not corrupt the snapshot's lookups.
- **F: giving the snapshotter its own aliased URLs for both archives changed nothing (0/12).** If the MapView were the collider, partitioning the cache by URL would have fixed it.

The collision is **between concurrent `MLNMapSnapshotter` instances**. Two snapshotters constructed with equal `ResourceOptions` are handed the *same* `PMTilesFileSource` by `FileSourceManager`, so they share one `directory_cache` / `directory_cache_control` pair and race to store the same directories — the duplicate-append + eviction bug analysed above. The MapView evidently resolves to a different file source instance and never joins the party. Aliasing can't separate two snapshotters from each other (they'd share whatever URL we alias to), which is why F failed.

Overlap is the whole variable, and failure scales with it: 1 renderer = never, 2 simultaneous = 2/12 fail, 2 staggered by a turn = 11/12 fail, 5+2 = 6/12 fail.

### What this means for the app today

- The shipping launch-time render is a *single* renderer, so it is safe on its own — the 10/12 measured earlier was an artifact of the spike being a second consumer.
- The real exposure is **overlapping renders**: `.onAppear` + `.onChange(of: previewSignature)`, or rapid trip switching, firing a second render while one is in flight. `TripPreviewRenderer` currently has no gate — `inFlight` is a dictionary precisely so concurrent renders are allowed.
- Timing/idle gating (G) works only by removing overlap. It is a weaker restatement of serialization and cannot help when two triggers land close together mid-session.

## Solution matrix (post-data)

| vector | verdict |
|---|---|
| Serialize renders — single slot, newest-wins queue | **Validated 44/44.** Also deletes the unbounded `inFlight` map and makes the async API viable again. Recommended. |
| Aliased archive URLs per consumer | **Dead — measured 0/12.** Cannot separate snapshotter from snapshotter. |
| Idle/delay gating | Works (12/12) but only as a proxy for "don't overlap"; strictly weaker than serializing, and no help mid-session. Skip if we serialize. |
| Upstream patch + PR to maplibre-native | Still the real fix, still worth sending. Independent of what we ship; the app-side gate stops us depending on the release cycle. |
| Own PMTiles reader for previews | Unnecessary now — serialization is ~20 lines against a much larger rewrite. |

## Summary of Changes

`TripPreviewRenderer` now renders one snapshot at a time behind a depth-1, newest-wins queue (`active` + `queued`), replacing the `inFlight` dictionary that existed specifically to allow concurrent renders. Completions are called exactly once — with nil on failure, and with nil when a newer request supersedes one that never ran.

Shipping build, original two-consumer configuration: **12/12** (was 10/12; 1/12 when the renders were staggered).

Follow-ups: AlaskaRouter-ydjf (upstream PR — the actual fix), AlaskaRouter-wq1q (async shape, now unblocked).
