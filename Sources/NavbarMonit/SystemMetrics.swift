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

    // Previous CPU tick state, used to compute the delta.
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func sample() -> Snapshot {
        Snapshot(cpu: cpuUsage(), ram: ramUsage(), disk: diskUsage())
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

    private func ramUsage() -> Double {
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
        let used = active + wired + compressed

        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return max(0, min(1, used / total))
    }

    // MARK: - Disk

    private func diskUsage() -> Double {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacityForImportantUsage,
        total > 0 else { return 0 }

        let used = Double(total) - Double(available)
        return max(0, min(1, used / Double(total)))
    }

    // MARK: - Helpers for the detailed display

    static func diskDetail() -> (usedGB: Double, totalGB: Double) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacityForImportantUsage else {
            return (0, 0)
        }
        let gb = 1_000_000_000.0
        let used = Double(total - Int(available)) / gb
        return (used, Double(total) / gb)
    }

    static func ramTotalGB() -> Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }
}
