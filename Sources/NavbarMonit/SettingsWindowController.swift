import Cocoa

/// A small preferences window: login item, display mode and refresh interval.
final class SettingsWindowController: NSWindowController {

    private let startAtLogin = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let refreshOptions: [(label: String, value: Double)] = [
        ("1 second", 1), ("2 seconds", 2), ("5 seconds", 5), ("10 seconds", 10)
    ]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 188),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "NavbarMonit Settings"
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
        syncFromSettings()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.alignment = .right
            return l
        }

        startAtLogin.target = self
        startAtLogin.action = #selector(loginToggled)

        displayPopup.addItems(withTitles: ["Packed (stacked)", "Flat (side by side)"])
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)

        refreshPopup.addItems(withTitles: refreshOptions.map(\.label))
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshChanged)

        let displayLabel = label("Display:")
        let refreshLabel = label("Refresh every:")

        let grid = NSGridView(views: [
            [NSGridCell.emptyContentView, startAtLogin],
            [displayLabel, displayPopup],
            [refreshLabel, refreshPopup],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        content.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    private func syncFromSettings() {
        startAtLogin.state = LoginItem.isEnabled ? .on : .off
        displayPopup.selectItem(at: Settings.shared.displayMode == .packed ? 0 : 1)
        let interval = Settings.shared.refreshInterval
        if let idx = refreshOptions.firstIndex(where: { $0.value == interval }) {
            refreshPopup.selectItem(at: idx)
        }
    }

    func showCentered() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Actions

    @objc private func loginToggled() {
        LoginItem.setEnabled(startAtLogin.state == .on)
        // Reflect the real state in case registration failed.
        startAtLogin.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func displayChanged() {
        Settings.shared.displayMode = displayPopup.indexOfSelectedItem == 0 ? .packed : .flat
    }

    @objc private func refreshChanged() {
        Settings.shared.refreshInterval = refreshOptions[refreshPopup.indexOfSelectedItem].value
    }
}
