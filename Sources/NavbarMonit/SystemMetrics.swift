import Foundation
import Darwin

/// Collects system metrics: CPU, RAM, disk.
/// No external dependencies — only Mach/BSD APIs.
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

    // Previous CPU tick state, used to compute the delta.
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

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

        let userDiff = Double(user &- prev.user)
        let systemDiff = Double(system &- prev.system)
        let idleDiff = Double(idle &- prev.idle)
        let niceDiff = Double(nice &- prev.nice)

        let busy = userDiff + systemDiff + niceDiff
        let total = busy + idleDiff
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

    // MARK: - Disk

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
}
