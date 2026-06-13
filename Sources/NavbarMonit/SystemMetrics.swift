import Foundation
import Darwin
import IOKit
import IOKit.ps

/// Collects system metrics: CPU, RAM, disk, network, disk I/O, battery, top processes.
/// No third-party dependencies — only Mach/BSD/IOKit APIs (plus `/bin/ps` for processes).
final class SystemMetrics {

    struct Snapshot {
        var cpu: Double   // 0.0 ... 1.0
        var ram: Double   // 0.0 ... 1.0
        var disk: Double  // 0.0 ... 1.0
    }

    /// Human-readable detail for a metric, in gigabytes.
    struct Detail {
        var usedGB: Double
        var totalGB: Double
        var availGB: Double
    }

    struct Rate {
        var inBytes: Double   // bytes / second
        var outBytes: Double  // bytes / second
    }

    struct Battery {
        var level: Double     // 0.0 ... 1.0
        var charging: Bool
    }

    // Per-instance state for delta-based metrics.
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNet: (rx: UInt64, tx: UInt64, time: Double)?
    private var previousIO: (read: UInt64, write: UInt64, time: Double)?

    func sample() -> Snapshot {
        Snapshot(cpu: cpuUsage(), ram: Self.ramUsage(), disk: Self.diskUsage())
    }

    // MARK: - CPU

    private func cpuUsage() -> Double {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = loadInfo.cpu_ticks.0
        let system = loadInfo.cpu_ticks.1
        let idle = loadInfo.cpu_ticks.2
        let nice = loadInfo.cpu_ticks.3

        defer { previousCPUTicks = (user, system, idle, nice) }
        guard let prev = previousCPUTicks else { return 0 }

        let busy = Double(user &- prev.user) + Double(system &- prev.system) + Double(nice &- prev.nice)
        let total = busy + Double(idle &- prev.idle)
        guard total > 0 else { return 0 }
        return max(0, min(1, busy / total))
    }

    // MARK: - RAM

    /// Used RAM in bytes: active + wired + compressed pages.
    private static func ramUsedBytes() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        return active + wired + compressed
    }

    private static func ramTotalBytes() -> Double {
        Double(ProcessInfo.processInfo.physicalMemory)
    }

    static func ramUsage() -> Double {
        let total = ramTotalBytes()
        guard total > 0 else { return 0 }
        return max(0, min(1, ramUsedBytes() / total))
    }

    static func ramDetail() -> Detail {
        let gb = 1_073_741_824.0
        let total = ramTotalBytes()
        let used = ramUsedBytes()
        return Detail(usedGB: used / gb, totalGB: total / gb, availGB: max(0, total - used) / gb)
    }

    // MARK: - Disk capacity

    private static func diskBytes() -> (total: Double, available: Double) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacityForImportantUsage else {
            return (0, 0)
        }
        return (Double(total), Double(available))
    }

    static func diskUsage() -> Double {
        let b = diskBytes()
        guard b.total > 0 else { return 0 }
        return max(0, min(1, (b.total - b.available) / b.total))
    }

    static func diskDetail() -> Detail {
        let gb = 1_000_000_000.0
        let b = diskBytes()
        return Detail(usedGB: (b.total - b.available) / gb, totalGB: b.total / gb, availGB: b.available / gb)
    }

    // MARK: - Network throughput

    private static func networkTotals() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            if let addr = cur.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               (flags & IFF_LOOPBACK) == 0,
               let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self)
                rx += UInt64(d.pointee.ifi_ibytes)
                tx += UInt64(d.pointee.ifi_obytes)
            }
            ptr = cur.pointee.ifa_next
        }
        return (rx, tx)
    }

    func networkRate() -> Rate {
        let now = ProcessInfo.processInfo.systemUptime
        let cur = Self.networkTotals()
        defer { previousNet = (cur.rx, cur.tx, now) }
        guard let prev = previousNet, now > prev.time else { return Rate(inBytes: 0, outBytes: 0) }
        let dt = now - prev.time
        return Rate(inBytes: max(0, Double(cur.rx &- prev.rx) / dt),
                    outBytes: max(0, Double(cur.tx &- prev.tx) / dt))
    }

    // MARK: - Disk I/O throughput (IOKit)

    private static func diskIOTotals() -> (read: UInt64, write: UInt64) {
        var read: UInt64 = 0
        var write: UInt64 = 0
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (read, write)
    }

    func diskIORate() -> Rate {
        let now = ProcessInfo.processInfo.systemUptime
        let cur = Self.diskIOTotals()
        defer { previousIO = (cur.read, cur.write, now) }
        guard let prev = previousIO, now > prev.time else { return Rate(inBytes: 0, outBytes: 0) }
        let dt = now - prev.time
        return Rate(inBytes: max(0, Double(cur.read &- prev.read) / dt),
                    outBytes: max(0, Double(cur.write &- prev.write) / dt))
    }

    // MARK: - Battery (IOKit.ps)

    static func batteryInfo() -> Battery? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
                  let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 else { continue }
            let charging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            return Battery(level: Double(current) / Double(max), charging: charging)
        }
        return nil
    }

    // MARK: - Top process (via /bin/ps)

    /// The single heaviest process by CPU or memory. Returns nil if `ps` is unavailable.
    static func topProcess(byCPU: Bool) -> (name: String, percent: Double)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -r sorts by CPU, -m by memory; -c gives the executable name only.
        process.arguments = byCPU ? ["-Aceo", "pcpu=,comm=", "-r"]
                                  : ["-Aceo", "pmem=,comm=", "-m"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " ") else { continue }
            // `ps` formats numbers with the locale's decimal separator (e.g. "39,8").
            let valueText = trimmed[..<space].replacingOccurrences(of: ",", with: ".")
            guard let value = Double(valueText) else { continue }
            let name = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return (name, value) }
        }
        return nil
    }

    // MARK: - Formatting helpers

    /// Formats a byte-rate as "12 KB/s", "1.4 MB/s", etc.
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSecond
        var i = 0
        while value >= 1024, i < units.count - 1 { value /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", value, units[i])
    }
}
