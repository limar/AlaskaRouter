// Always-visible scale indicator (bottom-left of the map, above attribution).
//
// Picks a "nice" rounded distance (e.g. 5 km, 10 mi, 100 m) close to a target
// pixel width and draws a thin bar of that scaled length. Auto-formats km/mi
// based on `Locale.current.measurementSystem`.

import SwiftUI
import MapLibreSwiftUI
import CoreLocation

struct ScaleIndicator: View {
    let camera: MapViewCamera
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

    private func info() -> ScaleInfo? {
        guard case let .centered(coord, zoom, _, _, _) = camera.state else { return nil }
        // Standard slippy-map meters-per-pixel at given latitude/zoom.
        let metersPerPixel = 156543.03 * cos(coord.latitude * .pi / 180) / pow(2, zoom)
        let targetMeters = Double(targetWidth) * metersPerPixel
        let imperial = Locale.current.measurementSystem == .us
        let candidates: [Double] = imperial
            ? [10, 25, 50, 100, 250, 500, 1000, 2500, 5280, 26400, 52800, 158400, 528000, 1320000, 5280000]
            : [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000]
        let pick = candidates.last(where: { $0 <= targetMeters }) ?? candidates.first ?? 1000
        let barWidth = CGFloat(pick / metersPerPixel)
        let label = formatDistance(meters: pick, imperial: imperial)
        return ScaleInfo(label: label, barWidth: barWidth)
    }

    private func formatDistance(meters: Double, imperial: Bool) -> String {
        if imperial {
            // Display in feet under 1 mile, miles above.
            let feet = meters * 3.28084
            if feet < 5280 { return "\(Int(feet.rounded())) ft" }
            let miles = meters / 1609.34
            if miles < 10 { return String(format: "%.1f mi", miles) }
            return "\(Int(miles.rounded())) mi"
        } else {
            if meters < 1000 { return "\(Int(meters.rounded())) m" }
            let km = meters / 1000
            if km < 10 { return String(format: "%.1f km", km) }
            return "\(Int(km.rounded())) km"
        }
    }
}
