import SwiftUI
import SwiftData

@main
struct AlaskaRouterApp: App {
    /// Single shared SwiftData stack (local-only v1, schema designed to be
    /// CloudKit-compatible later).
    let container: ModelContainer = {
        let schema = Schema([Trip.self, Waypoint.self, BlockSeparator.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to build ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
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
