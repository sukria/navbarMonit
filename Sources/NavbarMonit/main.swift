import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let metrics = SystemMetrics()
    private var timer: Timer?

    // Menu rows updated live.
    private var cpuMenuItem: NSMenuItem!
    private var ramMenuItem: NSMenuItem!
    private var diskMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly

        buildMenu()

        // First sample (CPU stays at 0 until we have a delta).
        _ = metrics.sample()
        update()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func buildMenu() {
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
        menu.addItem(NSMenuItem(title: "Quit NavbarMonit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func update() {
        let s = metrics.sample()
        statusItem.button?.image = Self.renderBars(cpu: s.cpu, ram: s.ram, disk: s.disk)

        cpuMenuItem.title = String(format: "CPU    %3.0f %%", s.cpu * 100)
        ramMenuItem.title = String(format: "RAM    %3.0f %%  (%.0f GB)", s.ram * 100, SystemMetrics.ramTotalGB())
        let disk = SystemMetrics.diskDetail()
        diskMenuItem.title = String(format: "Disk   %3.0f %%  (%.0f / %.0f GB)",
                                    s.disk * 100, disk.usedGB, disk.totalGB)
    }

    // MARK: - Rendering the bars in the menu bar

    /// Green → yellow → red color depending on the usage ratio.
    private static func color(for value: Double) -> NSColor {
        let v = max(0, min(1, value))
        // hue 0.33 (green) down to 0.0 (red)
        let hue = (1.0 - v) * 0.33
        return NSColor(hue: hue, saturation: 0.85, brightness: 0.9, alpha: 1.0)
    }

    private static func renderBars(cpu: Double, ram: Double, disk: Double) -> NSImage {
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
            // Top (CPU) to bottom (Disk).
            let y = height - rowH - CGFloat(i) * (rowH + gap)

            // Label.
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
            NSString(string: labels[i]).draw(at: NSPoint(x: 0, y: y - 1), withAttributes: attrs)

            // Bar track.
            let track = NSRect(x: labelW, y: y, width: barW, height: rowH)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()

            // Fill.
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
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
