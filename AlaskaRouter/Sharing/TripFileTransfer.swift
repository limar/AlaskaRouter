// Custom document type + Transferable wrapper for `.akrtrip` trip files
// (AlaskaRouter-h113).
//
// `UTType.alaskaRouterTrip` is the app's exported content type (declared in
// Info.plist under UTExportedTypeDeclarations + CFBundleDocumentTypes). It lets
// Files, AirDrop, the share sheet, and `.fileImporter` recognize the format and
// route a tapped/AirDropped file back into the app via `.onOpenURL`.

import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    /// Lossless AlaskaRouter trip document. JSON under the hood, so it conforms
    /// to `public.json`; the dedicated identifier is what makes Files/AirDrop
    /// hand the file back to this app on open.
    static var alaskaRouterTrip: UTType {
        UTType(exportedAs: "dev.alaskarouter.trip", conformingTo: .json)
    }

    /// File extension used on disk (without the dot).
    static let alaskaRouterTripExtension = "akrtrip"
}

/// A built document ready to hand to `ShareLink`. Carries the suggested file
/// name so the AirDrop/Files copy is named after the trip.
struct ExportedTripFile: Transferable {
    let document: TripDocument
    /// Base file name without extension (sanitized trip name).
    let baseName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .alaskaRouterTrip) { exported in
            let dir = FileManager.default.temporaryDirectory
            let url = dir.appendingPathComponent(exported.baseName)
                .appendingPathExtension(UTType.alaskaRouterTripExtension)
            try exported.document.jsonData().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { exported in
            "\(exported.baseName).\(UTType.alaskaRouterTripExtension)"
        }
    }
}

enum TripFileNaming {
    /// Turn a trip name into a filesystem-safe base name. Falls back to "Trip"
    /// when the name is empty or reduces to nothing after stripping.
    static func sanitizedBaseName(_ tripName: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.controlCharacters)
        let cleaned = tripName
            .components(separatedBy: illegal)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Trip" : cleaned
    }
}
