// Floating right-side map controls: zoom in, zoom out, locate-me.
//
// Buttons match the search bar aesthetic: thin-material capsules with subtle
// shadow + faint stroke + SF Symbol glyphs. Vertical stack, trailing edge.
// Crucial for gloved use AND for the simulator (where pinch-to-zoom is hard).

import SwiftUI
import MapLibreSwiftUI
import CoreLocation

struct MapControls: View {
    @Binding var camera: MapViewCamera
    /// Stub for now — wiring locate-me to CLLocationManager is a follow-up.
    var onLocateMe: (() -> Void)? = nil

    var body: some View {
        // Read live zoom from the camera; gate the +/− buttons against it.
        // The pinch gesture already clamps to TilePackManifest.effectiveMaxZoom
        // (see ExpeditionMapView). The "+" button used to ignore that, letting
        // the camera's local zoom drift past the map's actual clamp — which
        // visibly desynced the scale indicator (AlaskaRouter-i3jz).
        let currentZoom = currentZoomOrNil ?? 0
        let maxZoom = TilePackManifest.shared.effectiveMaxZoom
        let minZoom: Double = 0
        let canZoomIn  = currentZoom < maxZoom - 0.01
        let canZoomOut = currentZoom > minZoom + 0.01

        VStack(spacing: 10) {
            if onLocateMe != nil {
                button(systemImage: "location", enabled: true, action: onLocateMe ?? {})
            }
            button(systemImage: "plus",  enabled: canZoomIn,  action: zoomIn)
            button(systemImage: "minus", enabled: canZoomOut, action: zoomOut)
        }
    }

    private func button(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.45)
    }

    // MARK: - Zoom

    private func zoomIn()  { adjustZoom(by: +1) }
    private func zoomOut() { adjustZoom(by: -1) }

    private func adjustZoom(by delta: Double) {
        guard let (center, zoom, pitch, direction) = currentCentered() else { return }
        // Respect the pack's effective max zoom — same clamp the pinch gesture
        // uses on MLNMapView.maximumZoomLevel. Without this clamp, the camera's
        // local zoom drifts past the map's clamp; the scale indicator reads
        // the drifted value and miscomputes meters-per-pixel (i3jz).
        let maxZoom = TilePackManifest.shared.effectiveMaxZoom
        let newZoom = max(0, min(maxZoom, zoom + delta))
        if abs(newZoom - zoom) < 0.001 { return }    // no-op guard at limits
        withAnimation(.smooth(duration: 0.3)) {
            camera = .center(center, zoom: newZoom, pitch: pitch, direction: direction)
        }
    }

    private var currentZoomOrNil: Double? {
        if case let .centered(_, zoom, _, _, _) = camera.state { return zoom }
        return nil
    }

    private func currentCentered() -> (CLLocationCoordinate2D, Double, Double, CLLocationDirection)? {
        if case let .centered(coord, zoom, pitch, _, direction) = camera.state {
            return (coord, zoom, pitch, direction)
        }
        return nil
    }
}
