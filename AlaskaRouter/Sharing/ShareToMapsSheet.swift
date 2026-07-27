// Custom app-chooser for exporting a place to an external maps app
// (AlaskaRouter-55pn). Preferred over the system share sheet: it shows exactly
// the four maps apps we support, as recognizable tiles, and hides the ones the
// user doesn't have installed instead of burying them in a generic list.
//
// Availability is decided by `canOpenURL` on each app's scheme probe. Apple
// Maps is always present (universal https link), so on the Simulator — where no
// App Store apps exist — this sheet shows Apple Maps alone, which is expected.

import SwiftUI
import UIKit

/// The trailing "Share" icon button used in both PreviewCallout and
/// StopCallout. Sized to sit beside the primary pill / Remove button at equal
/// height, so the right-hand Share slot looks identical across callouts.
struct ShareCalloutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share place")
    }
}

struct ShareToMapsSheet: View {
    let place: SharePlace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Apps actually openable on this device, computed once on appear.
    private var availableApps: [MapApp] {
        // Dev screenshot hook (a44b) — the Simulator has no App Store apps, so
        // without this the multi-row layout can never be captured there.
        if LaunchArgs.shareSheetShowsAllApps { return MapApp.allCases }
        return MapApp.allCases.filter { app in
            guard let probe = app.probeURL else { return true }   // Apple Maps
            return UIApplication.shared.canOpenURL(probe)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 16)]

    /// Measured content height, which drives the detent (AlaskaRouter-a44b).
    /// The old hard-coded `.height(220)` fitted exactly one row of tiles: with
    /// 4 apps installed the adaptive grid wraps to two rows on an iPhone-width
    /// sheet, the content overflowed, and the header got pushed under the top
    /// edge. Measuring means it fits 1, 2 or 3 rows without a magic number.
    /// Seeded at the old value so the first layout pass isn't zero-height.
    @State private var contentHeight: CGFloat = 220

    /// Clearance under the sheet's top edge for `presentationDragIndicator`,
    /// which draws *inside* the sheet — `.padding(.top, 4)` was not enough and
    /// the grabber sat on the title.
    private let dragIndicatorClearance: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open in…")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                if let name = place.cleanName {
                    Text(name)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, dragIndicatorClearance)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(availableApps) { app in
                    Button {
                        open(app)
                    } label: {
                        appTile(app)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    private func appTile(_ app: MapApp) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol(for: app))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(tint(for: app), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            Text(app.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 84)
    }

    private func open(_ app: MapApp) {
        let url = PlaceShareURL.url(for: app, place: place)
        openURL(url)
        dismiss()
    }

    // Brand logos aren't in SF Symbols (and shipping them raises trademark
    // questions for an OSS app), so we use a distinct symbol + tint per app.
    // Real brand icons can drop in here later as asset catalogs.
    private func symbol(for app: MapApp) -> String {
        switch app {
        case .appleMaps:  return "map.fill"
        case .googleMaps: return "mappin.and.ellipse"
        case .waze:       return "car.fill"
        case .mapsme:     return "globe.americas.fill"
        }
    }

    private func tint(for app: MapApp) -> Color {
        switch app {
        case .appleMaps:  return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .googleMaps: return Color(red: 0.91, green: 0.30, blue: 0.24)
        case .waze:       return Color(red: 0.20, green: 0.74, blue: 0.90)
        case .mapsme:     return Color(red: 0.25, green: 0.66, blue: 0.42)
        }
    }
}
