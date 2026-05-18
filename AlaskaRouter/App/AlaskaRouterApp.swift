import SwiftUI

@main
struct AlaskaRouterApp: App {
    var body: some Scene {
        WindowGroup {
            // Note: do NOT .ignoresSafeArea() here — it would cascade to the floating
            // chrome and force it under the Dynamic Island. RootView handles ignoring
            // safe area only on the map layer, leaving the search bar to respect it.
            RootView()
        }
    }
}
