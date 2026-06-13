import Cocoa

/// Preferences window: login item, which bars to show, layout, color threshold,
/// refresh interval, and which detail rows appear in the dropdown menu.
final class SettingsWindowController: NSWindowController {

    // Checkbox tags → matched in `checkboxChanged`.
    private enum Tag: Int {
        case login = 1, cpu, ram, disk, percent
        case network, diskIO, battery, topCPU, topRAM
    }

    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let thresholdPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var checkboxes: [Tag: NSButton] = [:]

    private let thresholdOptions: [(label: String, value: Double)] = [
        ("100%", 1.0), ("90%", 0.9), ("80%", 0.8)
    ]
    private let refreshOptions: [(label: String, value: Double)] = [
        ("1 second", 1), ("2 seconds", 2), ("5 seconds", 5), ("10 seconds", 10)
    ]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 470),
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

    // MARK: - Layout

    private func checkbox(_ title: String, _ tag: Tag) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged(_:)))
        b.tag = tag.rawValue
        checkboxes[tag] = b
        return b
    }

    private func header(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text.uppercased())
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func popupRow(_ title: String, _ popup: NSPopUpButton) -> NSView {
        let label = NSTextField(labelWithString: title)
        let row = NSStackView(views: [label, popup])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        displayPopup.addItems(withTitles: ["Packed (stacked)", "Flat (side by side)"])
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)

        thresholdPopup.addItems(withTitles: thresholdOptions.map(\.label))
        thresholdPopup.target = self
        thresholdPopup.action = #selector(thresholdChanged)

        refreshPopup.addItems(withTitles: refreshOptions.map(\.label))
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshChanged)

        let barsRow = NSStackView(views: [
            checkbox("CPU", .cpu), checkbox("RAM", .ram), checkbox("Disk", .disk)
        ])
        barsRow.orientation = .horizontal
        barsRow.spacing = 16

        let stack = NSStackView(views: [
            checkbox("Start at login", .login),

            header("Menu-bar bars"),
            barsRow,
            checkbox("Show percentage as text", .percent),
            popupRow("Layout:", displayPopup),
            popupRow("Turn red at:", thresholdPopup),
            popupRow("Refresh every:", refreshPopup),

            header("Menu details"),
            checkbox("Network throughput (↓/↑)", .network),
            checkbox("Disk I/O (read/write)", .diskIO),
            checkbox("Battery", .battery),
            checkbox("Top CPU process", .topCPU),
            checkbox("Top memory process", .topRAM),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])
    }

    private func syncFromSettings() {
        let s = Settings.shared
        checkboxes[.login]?.state = LoginItem.isEnabled ? .on : .off
        checkboxes[.cpu]?.state = s.showCPU ? .on : .off
        checkboxes[.ram]?.state = s.showRAM ? .on : .off
        checkboxes[.disk]?.state = s.showDisk ? .on : .off
        checkboxes[.percent]?.state = s.showPercentText ? .on : .off
        checkboxes[.network]?.state = s.showNetwork ? .on : .off
        checkboxes[.diskIO]?.state = s.showDiskIO ? .on : .off
        checkboxes[.battery]?.state = s.showBattery ? .on : .off
        checkboxes[.topCPU]?.state = s.showTopCPU ? .on : .off
        checkboxes[.topRAM]?.state = s.showTopRAM ? .on : .off

        displayPopup.selectItem(at: s.displayMode == .packed ? 0 : 1)
        if let i = thresholdOptions.firstIndex(where: { $0.value == s.redThreshold }) {
            thresholdPopup.selectItem(at: i)
        }
        if let i = refreshOptions.firstIndex(where: { $0.value == s.refreshInterval }) {
            refreshPopup.selectItem(at: i)
        }
    }

    func showCentered() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Actions

    @objc private func checkboxChanged(_ sender: NSButton) {
        let on = sender.state == .on
        let s = Settings.shared
        switch Tag(rawValue: sender.tag) {
        case .login:
            LoginItem.setEnabled(on)
            sender.state = LoginItem.isEnabled ? .on : .off // reflect real state
        case .cpu:     s.showCPU = on
        case .ram:     s.showRAM = on
        case .disk:    s.showDisk = on
        case .percent: s.showPercentText = on
        case .network: s.showNetwork = on
        case .diskIO:  s.showDiskIO = on
        case .battery: s.showBattery = on
        case .topCPU:  s.showTopCPU = on
        case .topRAM:  s.showTopRAM = on
        case .none:    break
        }
    }

    @objc private func displayChanged() {
        Settings.shared.displayMode = displayPopup.indexOfSelectedItem == 0 ? .packed : .flat
    }

    @objc private func thresholdChanged() {
        Settings.shared.redThreshold = thresholdOptions[thresholdPopup.indexOfSelectedItem].value
    }

    @objc private func refreshChanged() {
        Settings.shared.refreshInterval = refreshOptions[refreshPopup.indexOfSelectedItem].value
    }
}
