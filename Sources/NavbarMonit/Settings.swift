import Foundation
import ServiceManagement

/// How the bars are laid out in the menu bar.
enum DisplayMode: String, CaseIterable {
    case packed  // three horizontal bars stacked vertically (compact)
    case flat    // three vertical bars side by side
}

/// User preferences, persisted in `UserDefaults`.
/// `onChange` is fired after any mutation so the UI can refresh.
final class Settings {
    static let shared = Settings()

    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let displayMode = "displayMode"
        static let refreshInterval = "refreshInterval"
    }

    private init() {}

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? "") ?? .packed }
        set { defaults.set(newValue.rawValue, forKey: Key.displayMode); onChange?() }
    }

    /// Sampling interval in seconds. Defaults to 2s.
    var refreshInterval: Double {
        get {
            let v = defaults.double(forKey: Key.refreshInterval)
            return v == 0 ? 2.0 : v
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval); onChange?() }
    }
}

/// Manages the "Start at login" state via the modern Service Management API.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("NavbarMonit: failed to update login item: \(error.localizedDescription)")
        }
    }
}
