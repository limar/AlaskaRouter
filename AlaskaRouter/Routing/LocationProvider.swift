// CoreLocation wrapper for AlaskaRouter-j03u (Locate me + GPS).
//
// SwiftUI-friendly @Observable that exposes the user's current authorization
// status + their latest fix. UI views read these reactively. The first call to
// requestWhenInUse() triggers the iOS permission prompt; subsequent calls
// are a no-op if already determined.
//
// Simulator: feed locations via Xcode's Debug → Location menu or
// `xcrun simctl location <udid> set <lat>,<lon>`. CLLocationManager picks
// them up the same way it would a real GPS fix.

import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationProvider: NSObject {
    /// Current authorization status. Drives the locate-me button's enabled
    /// state and the post-tap UX (request prompt vs. center on fix vs. nudge
    /// to Settings).
    var authorizationStatus: CLAuthorizationStatus

    /// Latest known fix. `nil` until the OS delivers the first one (briefly
    /// after permission is granted). Subsequent updates overwrite.
    var lastLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // We don't need sub-meter precision for trip-planning context;
        // 10 m is plenty and lets the OS coalesce updates.
        manager.distanceFilter = 10
    }

    /// Ask for when-in-use permission. Idempotent — iOS handles the
    /// duplicate request case.
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// Start receiving location updates. Call after permission is granted.
    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    /// True iff we have a "yes" answer from the user (when-in-use or always).
    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.startUpdating()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // We don't have a UI surface for transient errors. The blue dot will
        // simply stop updating; user can re-tap locate-me to retry.
    }
}
