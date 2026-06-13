import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let metrics = SystemMetrics()
    private var timer: Timer?
    private var settingsController: SettingsWindowController?

    // Latest readings, refreshed every tick; read by the menu and tooltip.
    private struct Readings {
        var cpu = 0.0, ram = 0.0, disk = 0.0
        var ramDetail = SystemMetrics.Detail(usedGB: 0, totalGB: 0, availGB: 0)
        var diskDetail = SystemMetrics.Detail(usedGB: 0, totalGB: 0, availGB: 0)
        var net = SystemMetrics.Rate(inBytes: 0, outBytes: 0)
        var io = SystemMetrics.Rate(inBytes: 0, outBytes: 0)
        var battery: SystemMetrics.Battery?
    }
    private var latest = Readings()

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        Settings.shared.onChange = { [weak self] in
            self?.restartTimer()
            self?.update()
        }

        _ = metrics.sample() // prime CPU delta
        update()
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Settings.shared.refreshInterval, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    // MARK: - Click handling

    /// Left click → readout menu. Right click (or ⌃-click) → settings window.
    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false)

        if isRight {
            openSettings()
        } else {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil // detach so our action fires again next time
        }
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.showCentered()
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Update loop

    private func update() {
        let s = metrics.sample()
        var r = Readings()
        r.cpu = s.cpu; r.ram = s.ram; r.disk = s.disk
        r.ramDetail = SystemMetrics.ramDetail()
        r.diskDetail = SystemMetrics.diskDetail()
        r.net = metrics.networkRate()  // sampled every tick to keep the delta fresh
        r.io = metrics.diskIORate()
        r.battery = SystemMetrics.batteryInfo()
        latest = r

        statusItem.button?.image = renderIcon()
        statusItem.button?.toolTip = tooltip()
    }

    // MARK: - Bars

    private struct Bar { let label: String; let value: Double }

    private func enabledBars() -> [Bar] {
        let s = Settings.shared
        var bars: [Bar] = []
        if s.showCPU { bars.append(Bar(label: "C", value: latest.cpu)) }
        if s.showRAM { bars.append(Bar(label: "R", value: latest.ram)) }
        if s.showDisk { bars.append(Bar(label: "D", value: latest.disk)) }
        return bars
    }

    private func renderIcon() -> NSImage {
        let bars = enabledBars()
        guard !bars.isEmpty else { return Self.renderEmpty() }
        switch Settings.shared.displayMode {
        case .packed: return Self.renderPacked(bars, showPercent: Settings.shared.showPercentText,
                                               threshold: Settings.shared.redThreshold)
        case .flat:   return Self.renderFlat(bars, showPercent: Settings.shared.showPercentText,
                                             threshold: Settings.shared.redThreshold)
        }
    }

    private func tooltip() -> String {
        var lines = [
            String(format: "CPU  %.0f%%", latest.cpu * 100),
            String(format: "RAM  %.0f%% (%.1f GB free)", latest.ram * 100, latest.ramDetail.availGB),
            String(format: "Disk  %.0f%% (%.0f GB free)", latest.disk * 100, latest.diskDetail.availGB),
        ]
        let s = Settings.shared
        if s.showNetwork {
            lines.append("Net  ↓ \(SystemMetrics.formatRate(latest.net.inBytes))  ↑ \(SystemMetrics.formatRate(latest.net.outBytes))")
        }
        if s.showDiskIO {
            lines.append("I/O  R \(SystemMetrics.formatRate(latest.io.inBytes))  W \(SystemMetrics.formatRate(latest.io.outBytes))")
        }
        if s.showBattery, let b = latest.battery {
            lines.append(String(format: "Battery  %.0f%%%@", b.level * 100, b.charging ? " (charging)" : ""))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Menu (built fresh on open)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared

        func info(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        info(String(format: "CPU    %3.0f %%", latest.cpu * 100))
        info(String(format: "RAM    %3.0f %%  (%.1f GB free)", latest.ram * 100, latest.ramDetail.availGB))
        info(String(format: "Disk   %3.0f %%  (%.0f GB free)", latest.disk * 100, latest.diskDetail.availGB))

        if s.showNetwork {
            info("Net    ↓ \(SystemMetrics.formatRate(latest.net.inBytes))   ↑ \(SystemMetrics.formatRate(latest.net.outBytes))")
        }
        if s.showDiskIO {
            info("I/O    R \(SystemMetrics.formatRate(latest.io.inBytes))   W \(SystemMetrics.formatRate(latest.io.outBytes))")
        }
        if s.showBattery, let b = latest.battery {
            info(String(format: "Battery %3.0f %%%@", b.level * 100, b.charging ? "  (charging)" : ""))
        }
        if s.showTopCPU, let p = SystemMetrics.topProcess(byCPU: true) {
            info(String(format: "Top CPU  %@  %.0f%%", p.name, p.percent))
        }
        if s.showTopRAM, let p = SystemMetrics.topProcess(byCPU: false) {
            info(String(format: "Top RAM  %@  %.0f%%", p.name, p.percent))
        }

        menu.addItem(.separator())

        let activity = NSMenuItem(title: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NavbarMonit",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: - Rendering

    /// Green → yellow → red. `threshold` is the usage at which the bar reaches full red.
    private static func color(for value: Double, threshold: Double) -> NSColor {
        let v = max(0, min(1, value / max(0.01, threshold)))
        let hue = (1.0 - v) * 0.33 // 0.33 green → 0.0 red
        return NSColor(hue: hue, saturation: 0.85, brightness: 0.9, alpha: 1.0)
    }

    private static let labelFont = NSFont.systemFont(ofSize: 6, weight: .semibold)

    private static func renderEmpty() -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        NSString(string: "M").draw(at: NSPoint(x: 2, y: 1), withAttributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        image.unlockFocus()
        return image
    }

    /// Horizontal bars stacked vertically — compact.
    private static func renderPacked(_ bars: [Bar], showPercent: Bool, threshold: Double) -> NSImage {
        let rowH: CGFloat = 5
        let gap: CGFloat = 2
        let labelW: CGFloat = 8
        let barW: CGFloat = 28
        let pctW: CGFloat = showPercent ? 20 : 0
        let width = labelW + barW + pctW
        let height = rowH * CGFloat(bars.count) + gap * CGFloat(max(0, bars.count - 1))

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        for (i, bar) in bars.enumerated() {
            let y = height - rowH - CGFloat(i) * (rowH + gap)

            NSString(string: bar.label).draw(at: NSPoint(x: 0, y: y - 1), withAttributes: [
                .font: labelFont, .foregroundColor: NSColor.labelColor
            ])

            let track = NSRect(x: labelW, y: y, width: barW, height: rowH)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()

            let v = max(0, min(1, bar.value))
            if v > 0 {
                let fill = NSRect(x: labelW, y: y, width: max(1.5, barW * v), height: rowH)
                color(for: bar.value, threshold: threshold).setFill()
                NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
            }

            if showPercent {
                NSString(string: String(format: "%.0f%%", bar.value * 100)).draw(
                    at: NSPoint(x: labelW + barW + 2, y: y - 1),
                    withAttributes: [.font: labelFont, .foregroundColor: NSColor.labelColor])
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Vertical bars side by side — easier to read at a glance.
    private static func renderFlat(_ bars: [Bar], showPercent: Bool, threshold: Double) -> NSImage {
        let barW: CGFloat = 5
        let gap: CGFloat = 5
        let labelH: CGFloat = 7
        let barMaxH: CGFloat = 10
        let width = barW * CGFloat(bars.count) + gap * CGFloat(max(0, bars.count - 1))
        let height = barMaxH + labelH

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        for (i, bar) in bars.enumerated() {
            let x = CGFloat(i) * (barW + gap)

            let track = NSRect(x: x, y: labelH, width: barW, height: barMaxH)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()

            let v = max(0, min(1, bar.value))
            if v > 0 {
                let fill = NSRect(x: x, y: labelH, width: barW, height: max(1.5, barMaxH * v))
                color(for: bar.value, threshold: threshold).setFill()
                NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
            }

            // Under each bar: the percentage (if enabled) or the metric letter.
            let caption = showPercent ? String(format: "%.0f", bar.value * 100) : bar.label
            let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.labelColor]
            let str = NSString(string: caption)
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: x + (barW - size.width) / 2, y: -1), withAttributes: attrs)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
