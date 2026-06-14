// Read a `.akrtrip` file URL into the store (AlaskaRouter-h113).
//
// Shared by both inbound paths: the in-app `.fileImporter` picker and
// `.onOpenURL` (a file tapped in Files or received over AirDrop). Both deliver
// a security-scoped URL that must be accessed inside a
// start/stopAccessingSecurityScopedResource bracket.

import Foundation
import SwiftData

@MainActor
enum TripFileImport {
    /// Read, decode and materialize the trip at `url`. Returns the inserted
    /// `Trip`. Throws `TripDocumentError` for an unsupported/newer file,
    /// `DecodingError` for malformed JSON, or a file-read error.
    @discardableResult
    static func importFile(
        at url: URL,
        into context: ModelContext,
        mode: TripImportMode = .copy
    ) throws -> Trip {
        // Security-scoped access is required for files outside the app sandbox
        // (the picker / AirDrop inbox). Harmless when not needed.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let doc = try TripDocument.decode(from: data)
        return doc.importTrip(into: context, mode: mode)
    }
}
