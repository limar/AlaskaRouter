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
}

enum FloatingSearchBarState: String {
    case expanded, collapsed
}
