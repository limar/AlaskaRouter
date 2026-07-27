import CoreLocation
import Foundation

/// Launch-argument-driven configuration so we can pin design states for screenshots
/// or A/B comparison without rebuilding. Set via:
///   xcrun simctl launch booted <bundle> -<key> <value>
enum LaunchArgs {

    /// Force the search bar into a particular state for screenshot evaluation.
    /// - collapsed (default resting state — map mode, trip-name pill; th0e)
    /// - expanded (skip straight to the full search pill)
    /// A normal launch is not "search active", so the bar rests collapsed;
    /// the screenshot override (`-barState expanded`) still pins it open. A
    /// launch that also sets a `prefillQuery` makes search active and the
    /// bar expands on its own (RootView.syncBarState).
    static var initialBarState: FloatingSearchBarState {
        let raw = UserDefaults.standard.string(forKey: "barState") ?? "collapsed"
        return FloatingSearchBarState(rawValue: raw) ?? .collapsed
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

    /// Override the initial camera center ("lat,lon") for screenshot
    /// evaluation — pair with `initialZoom` to pin an exact view (e.g. the
    /// Galbraith corridor for the minor-roads overlay, AlaskaRouter-levi).
    static var initialCenter: CLLocationCoordinate2D? {
        let raw = UserDefaults.standard.string(forKey: "initialCenter") ?? ""
        let parts = raw.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(coord) ? coord : nil
    }

    /// Open the bottom sheet directly to its trips-switcher mode (Step 3 of
    /// the new-trip flow). Dev-only — for screenshot evaluation.
    static var startInTripsMode: Bool {
        UserDefaults.standard.bool(forKey: "tripsMode")
    }

    /// Automatically fire the locate-me action shortly after launch. Used to
    /// screenshot the GPS / blue-dot flow without manual tapping. Pair with
    /// `xcrun simctl privacy booted grant location <bundle>` to skip the
    /// permission prompt.
    static var autoLocateMe: Bool {
        UserDefaults.standard.bool(forKey: "autoLocateMe")
    }

    /// Load the bundled demo-route.geojson as the initial snapped coords
    /// so screenshots show the real curvy snapped road line, not the
    /// straight-line dashed fallback. Dev-only.
    static var preloadDemoRoute: Bool {
        UserDefaults.standard.bool(forKey: "preloadDemoRoute")
    }

    /// Seed the Parks-Highway demo trip on first launch. Dev-only — by default
    /// the app bootstraps an empty trip ("Trip from <today>") instead.
    static var seedDemoTrip: Bool {
        UserDefaults.standard.bool(forKey: "seedDemoTrip")
    }

    /// AlaskaRouter-56kj spike — render an offline map snapshot at "lat,lon" on
    /// launch and write it to Documents/preview-spike.png, to prove the
    /// MLNMapSnapshotter resolves our pmtiles:// scheme. Dev-only.
    static var spikePreviewSnapshot: CLLocationCoordinate2D? {
        let raw = UserDefaults.standard.string(forKey: "spikePreview") ?? ""
        let parts = raw.split(separator: ",")
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }


    /// Force every maps app into the "Open in…" chooser regardless of what is
    /// actually installed. Dev-only: the Simulator has no App Store apps, so
    /// the sheet normally renders a single Apple Maps tile and the multi-row
    /// layout — the case that clipped the title in the field (AlaskaRouter-a44b)
    /// — can't be screenshotted there at all.
    static var shareSheetShowsAllApps: Bool {
        UserDefaults.standard.bool(forKey: "shareAllApps")
    }

    /// After prefill query results land, auto-trigger this action for screenshot
    /// capture: `preview:<index>` opens the preview callout; `add:<index>` runs
    /// the fast-add flow; `share:<index>` opens the "Open in…" chooser for that
    /// result. Index is into the results list.
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
