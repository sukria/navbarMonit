import Foundation
import ServiceManagement

/// How the menu-bar bars are laid out.
enum DisplayMode: String, CaseIterable {
    case packed  // horizontal bars stacked vertically (compact)
    case flat    // vertical bars side by side
}

/// User preferences, persisted in `UserDefaults`.
/// `onChange` fires after any mutation so the UI can refresh.
final class Settings {
    static let shared = Settings()

    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private init() {}

    private func bool(_ key: String, default def: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? def : defaults.bool(forKey: key)
    }

    // MARK: - Menu-bar bars (ratio metrics)

    var showCPU: Bool {
        get { bool("showCPU", default: true) }
        set { defaults.set(newValue, forKey: "showCPU"); onChange?() }
    }
    var showRAM: Bool {
        get { bool("showRAM", default: true) }
        set { defaults.set(newValue, forKey: "showRAM"); onChange?() }
    }
    var showDisk: Bool {
        get { bool("showDisk", default: true) }
        set { defaults.set(newValue, forKey: "showDisk"); onChange?() }
    }

    /// Draw the numeric percentage next to each bar.
    var showPercentText: Bool {
        get { bool("showPercentText", default: false) }
        set { defaults.set(newValue, forKey: "showPercentText"); onChange?() }
    }

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .packed }
        set { defaults.set(newValue.rawValue, forKey: "displayMode"); onChange?() }
    }

    /// Usage ratio at which a bar reaches full red (1.0, 0.9 or 0.8).
    var redThreshold: Double {
        get {
            let v = defaults.double(forKey: "redThreshold")
            return v == 0 ? 1.0 : v
        }
        set { defaults.set(newValue, forKey: "redThreshold"); onChange?() }
    }

    /// Sampling interval in seconds.
    var refreshInterval: Double {
        get {
            let v = defaults.double(forKey: "refreshInterval")
            return v == 0 ? 2.0 : v
        }
        set { defaults.set(newValue, forKey: "refreshInterval"); onChange?() }
    }

    // MARK: - Dropdown menu details

    var showNetwork: Bool {
        get { bool("showNetwork", default: true) }
        set { defaults.set(newValue, forKey: "showNetwork"); onChange?() }
    }
    var showDiskIO: Bool {
        get { bool("showDiskIO", default: false) }
        set { defaults.set(newValue, forKey: "showDiskIO"); onChange?() }
    }
    var showBattery: Bool {
        get { bool("showBattery", default: true) }
        set { defaults.set(newValue, forKey: "showBattery"); onChange?() }
    }
    var showTopCPU: Bool {
        get { bool("showTopCPU", default: false) }
        set { defaults.set(newValue, forKey: "showTopCPU"); onChange?() }
    }
    var showTopRAM: Bool {
        get { bool("showTopRAM", default: false) }
        set { defaults.set(newValue, forKey: "showTopRAM"); onChange?() }
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
