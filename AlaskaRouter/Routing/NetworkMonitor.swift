// Thin wrapper around NWPathMonitor that exposes a SwiftUI-friendly
// @Observable connection state. Used to trigger pendingSnap auto-refresh
// when the device returns from offline.

import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isOnline: Bool = false
    /// Fires (on the main actor) when we transition from offline → online.
    var onReconnect: (() -> Void)?

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "dev.alaskarouter.network")

    init() {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = (path.status == .satisfied)
                if !wasOnline && self.isOnline {
                    self.onReconnect?()
                }
            }
        }
        self.monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
