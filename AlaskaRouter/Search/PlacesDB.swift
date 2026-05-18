// Low-level SQLite handle for the FTS5 places database (offline OSM-derived
// gazetteer for Alaska, ~12,617 deduped POIs, ~3 MB on disk). Built once by
// Tools/build-pack/ from a Geofabrik extract. See SPIKE_FINDINGS.md.
//
// Opened with the `immutable=1` URI flag so SQLite skips all WAL/journal
// checks — required when the file lives in a read-only app-bundle path.

import Foundation
import SQLite3

nonisolated(unsafe) let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

/// `@unchecked Sendable`: SQLite's default build (SQLITE_THREADSAFE=1) is the
/// "serialized" mode — multiple threads may safely use the same connection
/// without external locking. We only use the connection in read-only mode so
/// there's no write contention to worry about either.
final class PlacesDB: @unchecked Sendable {
    let handle: OpaquePointer

    init(bundleResource name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "sqlite") else {
            fatalError("Missing \(name).sqlite in bundle")
        }
        // Use SQLite URI to set immutable=1; bypasses WAL/SHM and journal probing.
        let uri = "file://\(url.path)?immutable=1"
        var h: OpaquePointer?
        let rc = sqlite3_open_v2(
            uri, &h,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil
        )
        guard rc == SQLITE_OK, let h else {
            fatalError("PlacesDB open failed (rc=\(rc)): \(String(cString: sqlite3_errmsg(h)))")
        }
        self.handle = h
    }

    deinit { sqlite3_close(handle) }
}
