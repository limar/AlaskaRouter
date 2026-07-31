---
# AlaskaRouter-ydjf
title: Send the PMTiles directory-cache fix upstream to maplibre-native
status: todo
type: task
priority: low
created_at: 2026-07-31T19:47:54Z
updated_at: 2026-07-31T19:47:54Z
---

We diagnosed a real upstream bug while fixing AlaskaRouter-pq9g and worked around it app-side. The fix itself is small and belongs upstream.

`platform/default/src/mbgl/storage/pmtiles_file_source.cpp`, `storeDirectory` (unchanged between our pinned `ios-v6.26.0` and `main`):

```cpp
directory_cache.at(url).emplace(key, pmtiles::deserialize_directory(data));  // NO-OP if key exists
directory_cache_control.at(url).emplace_back(key);                          // ALWAYS appends
```

Concurrent first-time reads of the same directory (two `MLNMapSnapshotter`s sharing one `PMTilesFileSource`) store it twice: one map entry, two LRU-control entries. Past `MAX_DIRECTORY_CACHE_ENTRIES` the eviction erases a directory that is still live, and `getTileAddress`'s `directory_cache.at(url).at(key)` throws `std::out_of_range`. Because that continuation runs inside `getDirectory`'s `try`, the error surfaces mislabelled as `"Error parsing PMTiles directory: map::at: key not found"`.

```cpp
auto [it, inserted] = directory_cache.at(url).emplace(key, pmtiles::deserialize_directory(directoryData));
if (inserted) {
    directory_cache_control.at(url).emplace_back(key);
    if (directory_cache_control.at(url).size() > MAX_DIRECTORY_CACHE_ENTRIES) { /* evict */ }
}
```

Second, smaller issue in the same file: `getDirectory` calls `directory_cache_control.at(url).back()` without checking the vector is non-empty.

## Todo
- [ ] Reproduce in an upstream-friendly form (two concurrent snapshotters over one archive)
- [ ] Open the issue with the analysis from AlaskaRouter-pq9g
- [ ] PR the fix
- [ ] When it lands, bump the pin and re-measure — the app-side serialization can stay regardless (it is the right shape anyway)
