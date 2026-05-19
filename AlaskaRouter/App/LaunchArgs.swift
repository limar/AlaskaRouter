import Foundation

/// Launch-argument-driven configuration so we can pin design states for screenshots
/// or A/B comparison without rebuilding. Set via:
///   xcrun simctl launch booted <bundle> -<key> <value>
enum LaunchArgs {

    /// Force the search bar into a particular state for screenshot evaluation.
    /// - expanded (default initial state)
    /// - collapsed (skip straight to the compact view)
    static var initialBarState: FloatingSearchBarState {
        let raw = UserDefaults.standard.string(forKey: "barState") ?? "expanded"
        return FloatingSearchBarState(rawValue: raw) ?? .expanded
    }

    /// Pre-fill the search query at launch (for screenshot-driven evaluation
    /// since the simulator doesn't easily accept synthesized keyboard input).
    static var prefillQuery: String? {
        let raw = UserDefaults.standard.string(forKey: "prefillQuery") ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// Force the trip bottom sheet to a particular detent for screenshots.
    static var initialTripDetent: TripSheetDetent {
        switch UserDefaults.standard.string(forKey: "tripDetent") ?? "overview" {
        case "collapsed": return .collapsed
        case "full":      return .full
        default:          return .overview
        }
    }

    /// Pre-select waypoint at this index (0-based) in the active trip's
    /// orderedWaypoints, so screenshots of the "selected (sobresaliente)" icon
    /// style can be captured without manually tapping the bottom sheet.
    static var preselectStopIndex: Int? {
        let raw = UserDefaults.standard.string(forKey: "preselectStopIndex") ?? ""
        return Int(raw)
    }

    /// Pair with preselectStopIndex: keep the camera move but skip setting
    /// selectedWaypointID. Useful for A/B comparison of same-camera-no-selection
    /// vs same-camera-with-selection screenshots.
    static var cameraOnlyNoSelect: Bool {
        UserDefaults.standard.bool(forKey: "cameraOnly")
    }

    /// Override the initial camera zoom for screenshot evaluation. Useful for
    /// verifying world-skeleton (low zoom) and Alaska detail (high zoom) at
    /// boot without manual tapping. Reads `initialZoom` from UserDefaults.
    static var initialZoom: Double? {
        let raw = UserDefaults.standard.string(forKey: "initialZoom") ?? ""
        return Double(raw)
    }

    /// Open the bottom sheet directly to its trips-switcher mode (Step 3 of
    /// the new-trip flow). Dev-only — for screenshot evaluation.
    static var startInTripsMode: Bool {
        UserDefaults.standard.bool(forKey: "tripsMode")
    }

    /// Seed the Parks-Highway demo trip on first launch. Dev-only — by default
    /// the app bootstraps an empty trip ("Trip from <today>") instead.
    static var seedDemoTrip: Bool {
        UserDefaults.standard.bool(forKey: "seedDemoTrip")
    }

    /// After prefill query results land, auto-trigger this action for screenshot
    /// capture: `preview:<index>` opens the preview callout; `add:<index>` runs
    /// the fast-add flow. Index is into the results list.
    static var debugAutoAction: (kind: String, index: Int)? {
        let raw = UserDefaults.standard.string(forKey: "autoAction") ?? ""
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let i = Int(parts[1]) else { return nil }
        return (String(parts[0]), i)
    }
}

enum FloatingSearchBarState: String {
    case expanded, collapsed
}
