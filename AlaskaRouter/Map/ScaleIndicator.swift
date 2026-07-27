// Always-visible scale indicator (bottom-left of the map, above attribution).
//
// Picks a "nice" rounded distance (e.g. 5 km, 10 mi, 100 m) close to a target
// pixel width and draws a thin bar of that scaled length. Units follow the
// user's "Distances in miles" tweak, same as every other distance in the app.

import SwiftUI
import MapLibreSwiftUI
import CoreLocation

/// Live map resolution, published on every frame of a pan/pinch.
///
/// This exists so the scale bar can track the gesture *while the fingers are
/// still down* (AlaskaRouter-xogw). The `MapViewCamera` binding can't do that —
/// MapLibreSwiftUI only writes it back on `regionDidChange`, i.e. once the
/// gesture ends, which made the user zoom blind and correct afterwards.
///
/// It is a separate `@Observable` object rather than `@State` on RootView on
/// purpose: RootView never reads `metersPerPixel`, it only hands the object
/// down, so a realtime update invalidates *this indicator alone* instead of
/// re-running RootView's body 60×/second with a 54-stop trip in it.
@Observable
@MainActor
final class MapScaleReading {
    /// Ground meters per screen point at the map's current center and zoom.
    /// Zero until the style finishes loading and the first proxy arrives.
    private(set) var metersPerPixel: Double = 0

    func update(center: CLLocationCoordinate2D, zoom: Double) {
        // Standard slippy-map meters-per-pixel at given latitude/zoom.
        let value = 156543.03 * cos(center.latitude * .pi / 180) / pow(2, zoom)
        // A pure horizontal pan doesn't change the resolution. Skip the write
        // so we don't invalidate the view for an identical result — Observation
        // notifies on every set, equal or not.
        guard value != metersPerPixel else { return }
        metersPerPixel = value
    }
}

struct ScaleIndicator: View {
    let reading: MapScaleReading
    /// Target on-screen width for the bar (the chosen "nice" distance gets as
    /// close to this as possible without exceeding it).
    let targetWidth: CGFloat = 92

    var body: some View {
        if let info = info() {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.thinMaterial)
                        .frame(width: info.barWidth + 12, height: 12)
                    Capsule()
                        .fill(.primary.opacity(0.75))
                        .frame(width: info.barWidth, height: 3)
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        }
    }

    // MARK: - Scale math

    private struct ScaleInfo { let label: String; let barWidth: CGFloat }

    private static let footInMeters = 0.3048
    private static let mileInMeters = 1609.344

    /// "Nice" bar lengths, in meters. Both ladders are written in their own
    /// *display* unit and converted, never the other way round: the previous
    /// imperial ladder listed foot values (5280, 26400, …) but fed them to the
    /// meters-per-pixel math, so the bar landed on 3.3 mi / 16 mi / 33 mi
    /// instead of 1 mi / 5 mi / 10 mi (AlaskaRouter-o962).
    private static let imperialCandidates: [Double] =
        [10, 25, 50, 100, 250, 500, 1000, 2000].map { $0 * footInMeters }
        + [1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 6000].map { $0 * mileInMeters }

    private static let metricCandidates: [Double] =
        [10, 25, 50, 100, 250, 500]
        + [1, 2.5, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 10000].map { $0 * 1000 }

    private func info() -> ScaleInfo? {
        let metersPerPixel = reading.metersPerPixel
        guard metersPerPixel > 0 else { return nil }
        let targetMeters = Double(targetWidth) * metersPerPixel
        // Read through the @Observable store from inside `body`, so flipping
        // the tweak re-renders the indicator.
        let imperial = TweaksStore.shared.distanceUnitIsMiles
        let candidates = imperial ? Self.imperialCandidates : Self.metricCandidates
        let pick = candidates.last(where: { $0 <= targetMeters }) ?? candidates.first ?? 1000
        let barWidth = CGFloat(pick / metersPerPixel)
        let label = formatDistance(meters: pick, imperial: imperial)
        return ScaleInfo(label: label, barWidth: barWidth)
    }

    private func formatDistance(meters: Double, imperial: Bool) -> String {
        if imperial {
            // Display in feet under 1 mile, miles above.
            let feet = meters / Self.footInMeters
            if feet < 5280 { return "\(Int(feet.rounded())) ft" }
            let miles = meters / Self.mileInMeters
            if miles < 10 { return "\(prettyOneDecimal(miles)) mi" }
            return "\(Int(miles.rounded())) mi"
        } else {
            if meters < 1000 { return "\(Int(meters.rounded())) m" }
            let km = meters / 1000
            if km < 10 { return "\(prettyOneDecimal(km)) km" }
            return "\(Int(km.rounded())) km"
        }
    }

    /// Format a value with at most one decimal place, dropping the trailing
    /// `.0` for whole numbers (AlaskaRouter-i3jz). `5.0` → "5", `5.5` → "5.5",
    /// `0.5` → "0.5". Avoids the "5.0 km" noise the user reported at maximum
    /// zoom where the indicator stabilizes on round numbers.
    private func prettyOneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}
