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
}

enum FloatingSearchBarState: String {
    case expanded, collapsed
}
