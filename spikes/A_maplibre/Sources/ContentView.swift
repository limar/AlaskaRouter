// Map rendering spike.
// - Loads a free vector style from OpenFreeMap (no API key required).
// - Drops a single annotation at Denali summit (63.069 N, 151.006 W) using a MapLibre
//   SymbolLayer + LineLayer fed by an inline GeoJSON ShapeSource.
// - Lets us confirm: (a) MapLibreSwiftUI builds on Xcode 26.5 / iOS 26 SDK,
//   (b) annotations stay glued during pan/zoom/rotate, (c) we can drive style + layers
//   declaratively from SwiftUI.

import SwiftUI
import MapLibre
import MapLibreSwiftUI
import MapLibreSwiftDSL

// Spike C: back to Denali on a rich OpenMapTiles basemap (OpenFreeMap), styled
// with our muted paper expedition palette.
private let denali = CLLocationCoordinate2D(latitude: 63.0692, longitude: -151.0070)
private let labelAnchor = CLLocationCoordinate2D(latitude: 63.3000, longitude: -150.4000)

// Spike A.5: load the bundled PMTiles style. The style references a remote Protomaps
// sample .pmtiles via the `pmtiles://` URL scheme — verifies that MapLibre Native iOS's
// built-in PMTiles support (PR #2882, MLN_WITH_PMTILES) is enabled in the prebuilt
// xcframework shipped via swiftui-dsl's maplibre-gl-native-distribution v6.26.0.
private let styleURL: URL = {
    guard let url = Bundle.main.url(forResource: "style-expedition", withExtension: "json") else {
        fatalError("Missing style-expedition.json — check Resources are bundled.")
    }
    return url
}()

// Cycle through (zoom, pitch, bearing) tuples on tap to test "annotation stays glued".
private let cameraStops: [(zoom: Double, pitch: Double, bearing: Double)] = [
    (4.5,  0, 0),
    (6.5,  0, 0),
    (9.0,  0, 0),
    (9.0, 45, 30),
    (3.5,  0, 0),
]

struct ContentView: View {
    @State private var camera: MapViewCamera = .center(denali, zoom: 6.5)
    @State private var cameraStopIndex: Int = 0
    @State private var timer: Timer? = nil

    var body: some View {
        MapView(
            styleURL: styleURL,
            camera: $camera
        ) {
            // Point source: label anchor.
            let labelFeature = MLNPointFeature()
            labelFeature.coordinate = denali
            labelFeature.attributes = ["label": "Denali — North America's roof"]
            let labelSource = ShapeSource(identifier: "ann-label") {
                labelFeature
            }

            // Line source: arrow from off-peak anchor pointing at Denali.
            let arrowFeature = MLNPolylineFeature(coordinates: [labelAnchor, denali], count: 2)
            let arrowSource = ShapeSource(identifier: "ann-arrow") {
                arrowFeature
            }

            LineStyleLayer(identifier: "annotation-arrow", source: arrowSource)
                .lineColor(.systemOrange)
                .lineWidth(2.0)
                .lineOpacity(0.85)

            SymbolStyleLayer(identifier: "annotation-label", source: labelSource)
                .textFontNames(["Noto Sans Regular"])
                .textFontSize(17)
                .textColor(.label)
                .textHaloColor(.systemBackground)
                .textHaloWidth(1.5)
                .text(featurePropertyNamed: "label")
                .textAnchor("bottom")
                .textOffset(CGVector(dx: 0, dy: -1.2))
                .textAllowsOverlap(true)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            FloatingSearchBarPreview()
                .padding(.horizontal, 14)
                .padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 4) {
                Text("z\(cameraStops[cameraStopIndex].zoom, specifier: "%.1f")  p\(cameraStops[cameraStopIndex].pitch, specifier: "%.0f")°  b\(cameraStops[cameraStopIndex].bearing, specifier: "%.0f")°")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.trailing, 16)
            .padding(.bottom, 56)
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
                cycleCamera()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func cycleCamera() {
        cameraStopIndex = (cameraStopIndex + 1) % cameraStops.count
        let stop = cameraStops[cameraStopIndex]
        camera = .center(denali, zoom: stop.zoom, pitch: stop.pitch, direction: stop.bearing)
    }
}

// A bare-bones preview of the floating search bar from the brief, just to feel the layering.
struct FloatingSearchBarPreview: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Search places, peaks, fuel…")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .regular))
            Spacer()
            Circle()
                .fill(Color.orange.opacity(0.85))
                .frame(width: 22, height: 22)
                .overlay(Text("AK").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

#Preview {
    ContentView()
}
