import SwiftUI
import SwiftData

@main
struct AlaskaRouterApp: App {
    /// Single shared SwiftData stack (local-only v1, schema designed to be
    /// CloudKit-compatible later).
    let container: ModelContainer = {
        let schema = Schema([Trip.self, Waypoint.self, BlockSeparator.self, RouteSegment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to build ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            // AlaskaRouter-6p2v: under XCTest the host app's only job is to
            // launch so the test bundle can attach. Rendering RootView would
            // resolve the file-scope `styleURL` in ExpeditionMapView, which
            // fatalErrors if the gitignored `alaska-pack.pmtiles` asset is
            // missing — and that asset is not present in a clean checkout.
            // Production launches still go down the RootView branch and must
            // still abort hard if pmtiles is missing (a real packaging error
            // must not ship), so the fatalErrors stay intact.
            if isRunningUnderXCTest {
                EmptyView()
            } else {
                // Note: do NOT .ignoresSafeArea() here — it would cascade to the floating
                // chrome and force it under the Dynamic Island. RootView handles ignoring
                // safe area only on the map layer.
                RootView()
                    .modelContainer(container)
                    .onAppear {
                        if LaunchArgs.seedDemoTrip {
                            SampleTrip.seedIfEmpty(in: container.mainContext)
                        }
                        TripStore.bootstrapIfNeeded(in: container.mainContext)
                    }
            }
        }
    }

    private var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
