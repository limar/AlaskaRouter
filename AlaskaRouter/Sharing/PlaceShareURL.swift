// Export/share a place (waystop, POI, or dropped pin) to an external maps app.
//
// Design (AlaskaRouter-55pn):
//  - A *named* place (POI / named waystop) is sent as name + a center
//    coordinate. Discovery apps (Apple/Google) do the matching server-side and
//    bias to that center, so "Finger Mountain" resolves to the Alaska one, not
//    the BC one. We deliberately do NOT verify the match client-side — there is
//    no Places API in the loop, the coordinate center-bias *is* the
//    foolproofing, and the handoff stays instant (we only build a URL string).
//  - An *unnamed* place (dropped pin) is sent as bare coordinates.
//  - Nav apps (Waze / Maps.me) ignore the name and just take the coordinate;
//    Maps.me accepts a label for the pin.
//
// These are pure functions: (MapApp, SharePlace) -> URL. No UIKit, fully
// unit-testable (PlaceShareURLTests) so the exact formats are locked without a
// simulator or device.

import CoreLocation
import Foundation

/// A place to export. `name` nil/blank => unnamed dropped pin (coords only).
struct SharePlace: Equatable {
    let name: String?
    let coordinate: CLLocationCoordinate2D

    /// Trimmed name, or nil when blank — collapses "" and "   " to the
    /// dropped-pin path so callers don't have to pre-clean.
    var cleanName: String? {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !n.isEmpty else { return nil }
        return n
    }

    static func == (lhs: SharePlace, rhs: SharePlace) -> Bool {
        lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// External maps apps we can hand a place off to.
enum MapApp: String, CaseIterable, Identifiable {
    case appleMaps
    case googleMaps
    case waze
    case mapsme

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMaps:  return "Apple Maps"
        case .googleMaps: return "Google Maps"
        case .waze:       return "Waze"
        case .mapsme:     return "Maps.me"
        }
    }

    /// Whether the app surfaces a rich place card (photos / ratings) — used to
    /// decide if sending the name is worthwhile. Nav apps just route.
    var isDiscovery: Bool {
        switch self {
        case .appleMaps, .googleMaps: return true
        case .waze, .mapsme:          return false
        }
    }

    /// Scheme-only URL probed with `canOpenURL` to detect installation.
    /// `nil` => always available (Apple Maps via universal https link, which
    /// resolves even on the Simulator where no App Store apps are installed).
    /// NB: the non-nil schemes must be declared in `LSApplicationQueriesSchemes`
    /// (Info.plist) or `canOpenURL` returns false even when installed.
    var probeURL: URL? {
        switch self {
        case .appleMaps:  return nil
        case .googleMaps: return URL(string: "comgooglemaps://")
        case .waze:       return URL(string: "waze://")
        case .mapsme:     return URL(string: "mapsme://")
        }
    }
}

enum PlaceShareURL {

    /// The URL that opens `place` in `app`. Native scheme for Google/Waze/
    /// Maps.me (only ever shown when installed); universal https for Apple Maps.
    static func url(for app: MapApp, place: SharePlace) -> URL {
        let lat = coord(place.coordinate.latitude)
        let lon = coord(place.coordinate.longitude)
        let name = place.cleanName

        switch app {
        case .appleMaps:
            // q+ll => labeled pin at the coordinate; tapping reveals the rich
            // card. Coordinate is the anchor, so a wrong name can't send you
            // to the wrong place.
            if let name {
                return make("https://maps.apple.com/?q=\(enc(name))&ll=\(lat),\(lon)")
            }
            return make("https://maps.apple.com/?ll=\(lat),\(lon)")

        case .googleMaps:
            // q=name + center biases Google's search to the area. For a pin we
            // pass coords as the query so it drops a marker rather than
            // searching text.
            if let name {
                return make("comgooglemaps://?q=\(enc(name))&center=\(lat),\(lon)&zoom=14")
            }
            return make("comgooglemaps://?q=\(lat),\(lon)&center=\(lat),\(lon)&zoom=15")

        case .waze:
            // Navigation app: coordinate only, start routing immediately.
            return make("waze://?ll=\(lat),\(lon)&navigate=yes")

        case .mapsme:
            // Offline app: coordinate + optional pin label.
            if let name {
                return make("mapsme://map?v=1&ll=\(lat),\(lon)&n=\(enc(name))")
            }
            return make("mapsme://map?v=1&ll=\(lat),\(lon)")
        }
    }

    // MARK: - Encoding

    /// 6 decimal places (~0.11 m) is far more than enough and keeps URLs short.
    /// `%f` uses the C locale, so the decimal separator is always a dot — never
    /// a comma — regardless of the user's locale.
    private static func coord(_ v: CLLocationDegrees) -> String {
        String(format: "%.6f", v)
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .placeQueryValue) ?? s
    }

    /// Force-unwrap is safe: every string above is a hand-built, percent-encoded
    /// literal. A failure would be a programmer error caught by the unit tests,
    /// not a runtime condition — so we don't hide it behind an optional.
    private static func make(_ s: String) -> URL {
        guard let u = URL(string: s) else {
            preconditionFailure("PlaceShareURL produced an invalid URL: \(s)")
        }
        return u
    }
}

private extension CharacterSet {
    /// Query-*value* safe: starts from the legal query set and removes the
    /// sub-delimiters that would otherwise be read as structure (so spaces
    /// become %20, "&" / "+" / "=" / "?" / "#" / "/" get encoded).
    static let placeQueryValue: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=?#/;,")
        return set
    }()
}
