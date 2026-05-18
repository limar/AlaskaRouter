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
        VStack(spacing: 10) {
            if onLocateMe != nil {
                button(systemImage: "location", action: onLocateMe ?? {})
            }
            button(systemImage: "plus", action: zoomIn)
            button(systemImage: "minus", action: zoomOut)
        }
    }

    private func button(systemImage: String, action: @escaping () -> Void) -> some View {
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
    }

    // MARK: - Zoom

    private func zoomIn()  { adjustZoom(by: +1) }
    private func zoomOut() { adjustZoom(by: -1) }

    private func adjustZoom(by delta: Double) {
        guard let (center, zoom, pitch, direction) = currentCentered() else { return }
        let newZoom = max(0, min(20, zoom + delta))
        withAnimation(.smooth(duration: 0.3)) {
            camera = .center(center, zoom: newZoom, pitch: pitch, direction: direction)
        }
    }

    private func currentCentered() -> (CLLocationCoordinate2D, Double, Double, CLLocationDirection)? {
        if case let .centered(coord, zoom, pitch, _, direction) = camera.state {
            return (coord, zoom, pitch, direction)
        }
        return nil
    }
}
