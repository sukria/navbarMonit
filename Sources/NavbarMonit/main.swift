import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let metrics = SystemMetrics()
    private var timer: Timer?
    private var settingsController: SettingsWindowController?

    // Live menu rows.
    private var cpuMenuItem: NSMenuItem!
    private var ramMenuItem: NSMenuItem!
    private var diskMenuItem: NSMenuItem!
    private lazy var contextMenu = buildMenu()

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

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        cpuMenuItem = NSMenuItem(title: "CPU", action: nil, keyEquivalent: "")
        ramMenuItem = NSMenuItem(title: "RAM", action: nil, keyEquivalent: "")
        diskMenuItem = NSMenuItem(title: "Disk", action: nil, keyEquivalent: "")
        cpuMenuItem.isEnabled = false
        ramMenuItem.isEnabled = false
        diskMenuItem.isEnabled = false

        menu.addItem(cpuMenuItem)
        menu.addItem(ramMenuItem)
        menu.addItem(diskMenuItem)
        menu.addItem(.separator())

        let activity = NSMenuItem(title: "Open Activity Monitor",
                                  action: #selector(openActivityMonitor), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NavbarMonit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
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

        statusItem.button?.image = Self.render(mode: Settings.shared.displayMode,
                                               cpu: s.cpu, ram: s.ram, disk: s.disk)

        let ram = SystemMetrics.ramDetail()
        let disk = SystemMetrics.diskDetail()

        cpuMenuItem.title = String(format: "CPU    %3.0f %%", s.cpu * 100)
        ramMenuItem.title = String(format: "RAM    %3.0f %%  (%.1f GB free)", s.ram * 100, ram.availGB)
        diskMenuItem.title = String(format: "Disk   %3.0f %%  (%.0f GB free)", s.disk * 100, disk.availGB)

        statusItem.button?.toolTip = String(
            format: "CPU  %.0f%%\nRAM  %.0f%% (%.1f GB free)\nDisk  %.0f%% (%.0f GB free)",
            s.cpu * 100, s.ram * 100, ram.availGB, s.disk * 100, disk.availGB
        )
    }

    // MARK: - Rendering

    /// Green → yellow → red color depending on the usage ratio.
    private static func color(for value: Double) -> NSColor {
        let v = max(0, min(1, value))
        let hue = (1.0 - v) * 0.33 // 0.33 green → 0.0 red
        return NSColor(hue: hue, saturation: 0.85, brightness: 0.9, alpha: 1.0)
    }

    private static func render(mode: DisplayMode, cpu: Double, ram: Double, disk: Double) -> NSImage {
        switch mode {
        case .packed: return renderPacked(cpu: cpu, ram: ram, disk: disk)
        case .flat:   return renderFlat(cpu: cpu, ram: ram, disk: disk)
        }
    }

    /// Three horizontal bars stacked vertically — compact.
    private static func renderPacked(cpu: Double, ram: Double, disk: Double) -> NSImage {
        let labels = ["C", "R", "D"]
        let values = [cpu, ram, disk]

        let rowH: CGFloat = 5
        let gap: CGFloat = 2
        let labelW: CGFloat = 9
        let barW: CGFloat = 30
        let width = labelW + barW
        let height = rowH * 3 + gap * 2

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let font = NSFont.systemFont(ofSize: 6, weight: .semibold)

        for i in 0..<3 {
            let y = height - rowH - CGFloat(i) * (rowH + gap) // top (CPU) to bottom (Disk)

            NSString(string: labels[i]).draw(at: NSPoint(x: 0, y: y - 1), withAttributes: [
                .font: font, .foregroundColor: NSColor.labelColor
            ])

            let track = NSRect(x: labelW, y: y, width: barW, height: rowH)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()

            let v = max(0, min(1, values[i]))
            if v > 0 {
                let fill = NSRect(x: labelW, y: y, width: max(1.5, barW * v), height: rowH)
                color(for: v).setFill()
                NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Three vertical bars side by side, each with its own label — wider, easier to read.
    private static func renderFlat(cpu: Double, ram: Double, disk: Double) -> NSImage {
        let labels = ["C", "R", "D"]
        let values = [cpu, ram, disk]

        let barW: CGFloat = 5
        let gap: CGFloat = 5
        let labelH: CGFloat = 7
        let barMaxH: CGFloat = 10
        let width = barW * 3 + gap * 2
        let height = barMaxH + labelH

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let font = NSFont.systemFont(ofSize: 6, weight: .semibold)

        for i in 0..<3 {
            let x = CGFloat(i) * (barW + gap)

            // Track (full height) at the top of the image.
            let track = NSRect(x: x, y: labelH, width: barW, height: barMaxH)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()

            // Fill grows from the bottom of the track.
            let v = max(0, min(1, values[i]))
            if v > 0 {
                let fill = NSRect(x: x, y: labelH, width: barW, height: max(1.5, barMaxH * v))
                color(for: v).setFill()
                NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
            }

            // Label centered under the bar.
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            let str = NSString(string: labels[i])
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
