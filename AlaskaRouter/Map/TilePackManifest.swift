// Read-only parser for `alaska-pack.manifest.json`. Single source of truth
// for the bundled tile pack's coverage extent and zoom range — keeps the
// camera honest about what tiles actually exist (AlaskaRouter-5h4y).
//
// We intentionally read only the few fields we use today; if more become
// useful later (bbox-based fit-to-coverage etc.), add them here rather than
// stashing constants in random call sites.

import Foundation

/// Decoded view of `alaska-pack.manifest.json`. Loaded once at app start.
struct TilePackManifest: Decodable {
    let version: String
    let coverage: [Coverage]

    struct Coverage: Decodable {
        let name: String
        let minzoom: Int
        let maxzoom: Int
    }

    /// Highest tile zoom available anywhere in the pack. The map camera
    /// clamps to this — letting the user pinch past it produces upscaled
    /// pixelated rectangles, which directly violates the "no ugly" rule.
    var effectiveMaxZoom: Double {
        Double(coverage.map(\.maxzoom).max() ?? 10)
    }

    /// Lazy-loaded shared instance. Logs once on failure and falls back to a
    /// conservative z=10 cap so the app stays usable even if the bundle
    /// shifts unexpectedly.
    static let shared: TilePackManifest = {
        guard let url = Bundle.main.url(forResource: "alaska-pack.manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(TilePackManifest.self, from: data)
        else {
            print("[TilePackManifest] could not load manifest — defaulting effectiveMaxZoom=10")
            return TilePackManifest(
                version: "fallback",
                coverage: [.init(name: "fallback", minzoom: 0, maxzoom: 10)]
            )
        }
        return parsed
    }()
}
